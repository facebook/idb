/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
@_implementationOnly import ArgumentParser
import CoreMedia
import CoreVideo
@_implementationOnly import FBControlCore
import Foundation
@_implementationOnly import SimulatorVideo

/// Cut an independently playable clip out of a recording.
///
/// Decoded and re-encoded rather than copied. A recording carries a keyframe at its first frame and
/// then at most every `--key-frame-rate` seconds (4 by default), so a passthrough copy cannot begin
/// on a keyframe at an arbitrary boundary: it would have to start seconds early or open on a partial
/// frame. Re-encoding is what buys a clip that begins exactly where it was asked to.
struct Clip: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Cut an independently playable clip out of a recording")
  @Option(help: "Seconds into the recording the clip starts") var start: Double
  @Option(help: "Seconds into the recording the clip ends") var end: Double
  @Argument(help: "Recording to cut") var input: String
  @Argument(help: "Output .mp4 path") var output: String

  func validate() throws {
    guard start.isFinite, start >= 0 else {
      throw ValidationError("--start must be zero or more seconds")
    }
    guard end.isFinite, end > start else {
      throw ValidationError("--end must be later than --start")
    }
    guard (output as NSString).pathExtension.lowercased() == "mp4" else {
      throw ValidationError("Output must end in .mp4")
    }
    guard FileManager.default.fileExists(atPath: input) else {
      throw ValidationError("Input does not exist: \(input)")
    }
    guard !FileManager.default.fileExists(atPath: output),
      !FileManager.default.fileExists(atPath: output + ".json")
    else {
      throw ValidationError("Output already exists: \(output)")
    }
  }

  /// Cut the clip, describe it, and publish both at once.
  ///
  /// Everything is written into a directory this invocation owns and moved into place only once
  /// the clip and its report are both complete, so a failure anywhere — decoding, encoding,
  /// reading back what was written, or writing the report — publishes neither, and a file that
  /// appeared at the destination since `validate()` is not replaced.
  mutating func run() async throws {
    let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: false)
    let destination = URL(fileURLWithPath: output)
    let staging = try ClipStaging(for: destination)
    defer { staging.discard() }
    try await write(to: staging.clip)
    // Cancellation is cooperative, and finalising a file is not a cancellation point: a command
    // cancelled after the last sample can still reach here with a complete clip in hand. Nothing
    // is published after that point.
    try Task.checkCancellation()
    let report = try await RecordingReport.read(url: staging.clip, encoding: RecordingEncoding.h264.rawValue, startedAt: nil)
    try JSONEncoder().encode(report).write(to: staging.report, options: .atomic)
    try Task.checkCancellation()
    try staging.promote(to: destination)
    logger.info().log("Cut \(report.duration) seconds of \(input) to \(output)")
  }

  /// Decode the requested range and re-encode it, rebased so the clip's own zero is its first frame.
  ///
  /// The reader, the writer and every sample buffer stay local to this one function and are never
  /// captured into a `@Sendable` closure, so no AVFoundation object crosses an isolation boundary.
  private func write(to destination: URL) async throws {
    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw ClipError.noVideoTrack(input)
    }
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, start < duration else {
      throw ClipError.outsideRecording(start: start, duration: duration)
    }
    let (size, dataRate, transform) = try await track.load(
      .naturalSize, .estimatedDataRate, .preferredTransform)

    let from = CMTime(seconds: start, preferredTimescale: Self.timescale)
    let to = CMTime(seconds: min(end, duration), preferredTimescale: Self.timescale)
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: from, end: to)
    let source = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(source)

    let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    let sink = AVAssetWriterInput(mediaType: .video, outputSettings: Self.settings(for: ClipDimensions(size: size, dataRate: dataRate)))
    sink.expectsMediaDataInRealTime = false
    // Samples are copied at the size they are stored at, so the display orientation the recording
    // carries has to be carried over with them; without it a rotated recording plays sideways.
    sink.transform = transform
    guard writer.canAdd(sink) else {
      throw ClipError.cannotEncode
    }
    writer.add(sink)

    guard reader.startReading() else {
      throw ClipError.unreadable(reader.error)
    }
    guard writer.startWriting() else {
      throw ClipError.unwritable(writer.error)
    }
    // The range's start becomes the clip's time zero, so a player reports the clip's own duration
    // and a caller seeks with the clip's own offsets.
    writer.startSession(atSourceTime: from)

    do {
      try await transcode(from: source, to: sink, reader: reader, writer: writer)
    } catch {
      reader.cancelReading()
      if writer.status == .writing {
        writer.cancelWriting()
      }
      throw error
    }
    sink.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else {
      throw ClipError.unwritable(writer.error)
    }
  }

  /// Pull every decoded sample of the range through the encoder.
  ///
  /// Backpressure is waited out rather than spun on, and every wait re-reads the writer: an input
  /// that stops asking for data because the writer has failed or been cancelled never becomes
  /// ready again, so waiting on it without that check is a hang rather than a slow clip.
  private func transcode(
    from source: AVAssetReaderTrackOutput,
    to sink: AVAssetWriterInput,
    reader: AVAssetReader,
    writer: AVAssetWriter
  ) async throws {
    var frames = 0
    while true {
      try Task.checkCancellation()
      guard let sample = source.copyNextSampleBuffer() else {
        break
      }
      while !sink.isReadyForMoreMediaData {
        guard writer.status == .writing else {
          throw ClipError.unwritable(writer.error)
        }
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(5))
      }
      guard sink.append(sample) else {
        throw ClipError.unwritable(writer.error)
      }
      frames += 1
    }
    guard reader.status != .failed else {
      throw ClipError.unreadable(reader.error)
    }
    guard frames > 0 else {
      throw ClipError.noFrames(start: start, end: end)
    }
  }

  private static let timescale: CMTimeScale = 600

  /// A one-second keyframe interval, so seeking inside the clip lands close to the offset asked for
  /// rather than at a keyframe seconds earlier — the recording's own four-second interval is exactly
  /// what stops it being cut by a stream copy.
  private static func settings(for dimensions: ClipDimensions) -> [String: Any] {
    [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: dimensions.width,
      AVVideoHeightKey: dimensions.height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: dimensions.bitRate,
        AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
      ],
    ]
  }
}

enum ClipError: Error, LocalizedError {
  case noVideoTrack(String)
  case outsideRecording(start: Double, duration: Double)
  case noFrames(start: Double, end: Double)
  case cannotEncode
  case unreadable((any Error)?)
  case unwritable((any Error)?)

  var errorDescription: String? {
    switch self {
    case let .noVideoTrack(path): return "\(path) holds no video track to cut"
    case let .outsideRecording(start, duration): return "--start \(start) is not inside a \(duration) second recording"
    case let .noFrames(start, end): return "No frames fall between \(start) and \(end) seconds"
    case .cannotEncode: return "Cannot encode a clip as h264 at the recording's dimensions"
    case let .unreadable(error): return "Could not read the recording: \(Self.describe(error))"
    case let .unwritable(error): return "Could not write the clip: \(Self.describe(error))"
    }
  }

  private static func describe(_ error: (any Error)?) -> String {
    error.map { String(describing: $0) } ?? "unknown error"
  }
}
