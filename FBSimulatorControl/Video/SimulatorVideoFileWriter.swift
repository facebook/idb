/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import FBControlCore
import Foundation
import os

// MARK: - SimulatorVideoFileWriter

private enum SimulatorVideoFileWriterError: Error, LocalizedError {
  case assetWriterFailedToFinish(errorDescription: String)
  case firstSampleBufferMissingFormatDescription
  case cannotAddVideoInput
  case assetWriterFailedToStart(errorDescription: String)

  var errorDescription: String? {
    switch self {
    case let .assetWriterFailedToFinish(errorDescription):
      return "AVAssetWriter failed to finish writing: \(errorDescription)"
    case .firstSampleBufferMissingFormatDescription:
      return "First sample buffer has no format description"
    case .cannotAddVideoInput:
      return "AVAssetWriter cannot add the video input"
    case let .assetWriterFailedToStart(errorDescription):
      return "AVAssetWriter failed to start writing: \(errorDescription)"
    }
  }
}

/// Muxes encoded H.264, HEVC, or JPEG `CMSampleBuffer`s into MP4 or MOV using `AVAssetWriter` in
/// passthrough mode (no re-encode). The in-process simulator recorder uses this as the file sink for
/// the framebuffer→VideoToolbox encode pipeline.
///
/// The writer opens lazily on its first sample, rather than being prepared up front: passthrough
/// muxing needs that sample's `CMFormatDescription` as the `sourceFormatHint` before `AVAssetWriter`
/// can start writing, and the encoded format only exists once the encoder emits its first frame. Only
/// that first frame incurs the one-time setup and it is still appended (not dropped); `consume` runs
/// serially, so later frames never overlap it and append directly. The movie timeline is anchored at
/// the first sample's presentation timestamp; `finish`, called once after the encoder has flushed,
/// finalizes the `moov`.
///
/// Chapter markers are buffered at the current video position and written by `ChapterTrackMuxer`
/// once the video is finished.
///
/// @unchecked Sendable: `consume` runs inside the VideoToolbox output handler, and VideoToolbox
/// invokes a session's output handlers serially, so consumes never overlap each other. `finish` is
/// called once, from the recorder, after `stopStreaming` has flushed the encoder
/// (`VTCompressionSessionCompleteFrames`), so it never overlaps `consume`. The
/// timed-metadata path (`writeTimedMetadata`) arrives from other isolation domains (the stdin
/// handler), so the chapter state it shares with `consume`/`finish` lives under an `OSAllocatedUnfairLock`.
final class SimulatorVideoFileWriter: EncodedSampleConsumer, TimedMetadataConsumer, @unchecked Sendable {
  private let outputURL: URL
  private let fileType: AVFileType
  private let chaptersEnabled: Bool
  private let logger: any ControlCoreLogger

  /// How often the writer flushes an index fragment.
  ///
  /// Without this the whole index is written by `finishWriting` alone, so a finalize that fails --
  /// or a recorder that never reaches it -- leaves every encoded frame on disk with nothing
  /// describing where any of them are, and the file cannot be opened at all. Fragmenting bounds
  /// what an interrupted recording loses to the fragment in progress; five seconds costs ~0.1% in
  /// file size at 30fps.
  private static let movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)

  private var assetWriter: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var failed = false

  /// Chapter markers and the running video position, shared between the writeQueue (`consume`/`finish`)
  /// and the stdin handler (`writeTimedMetadata`).
  private struct ChapterState {
    var pendingChapters: [ChapterTrackMuxer.Marker] = []
    var firstPresentationTime: CMTime = .invalid
    var lastPresentationTime: CMTime = .invalid
  }
  private let chapters = OSAllocatedUnfairLock(initialState: ChapterState())

  /// The presentation timestamp `startSession` anchored the movie at, which is the file's media time
  /// zero. Distinct from `ChapterState.firstPresentationTime`, the first sample actually appended,
  /// which is only tracked when chapters are enabled. Read from the recorder's isolation domain.
  private let anchor = OSAllocatedUnfairLock(initialState: CMTime.invalid)

  /// The file's media time zero, or nil until the first sample has opened the writer.
  var startPresentationTime: CMTime? {
    let time = anchor.withLock { $0 }
    return time.isValid ? time : nil
  }

  init(filePath: String, fileType: AVFileType = .mp4, chaptersEnabled: Bool = false, logger: any ControlCoreLogger) {
    self.outputURL = URL(fileURLWithPath: filePath)
    self.fileType = fileType
    self.chaptersEnabled = chaptersEnabled
    self.logger = logger
  }

  // MARK: - EncodedSampleConsumer

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any ControlCoreLogger) -> Bool {
    if failed {
      return false
    }
    let input: AVAssetWriterInput
    do {
      input = try startIfNeeded(with: sampleBuffer)
    } catch {
      failed = true
      logger.log("AVAssetWriter failed to start: \(error)")
      return false
    }
    // Never block the encode queue: if the writer is behind, drop the frame. The encoder counts the
    // returned `false` as a write failure, matching the streaming consumer-overflow behavior.
    guard input.isReadyForMoreMediaData else {
      logger.log("AVAssetWriter input not ready for more media data, dropping frame")
      return false
    }
    guard input.append(sampleBuffer) else {
      failed = true
      logger.log("AVAssetWriter failed to append sample: \(assetWriter?.error.map { String(describing: $0) } ?? "unknown error")")
      return false
    }
    if chaptersEnabled {
      recordVideoPosition(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
    return true
  }

  // MARK: - TimedMetadataConsumer

  /// Buffer a chapter marker at the current video position. Written to the chapter track in `finish`.
  func writeTimedMetadata(_ text: String, logger: any ControlCoreLogger) {
    guard chaptersEnabled else {
      logger.log("writeTimedMetadata: chapters not enabled on this recording, dropping")
      return
    }
    // Timestamp the marker at the most recent frame; if none yet, anchor at the session start (filled
    // in once the first frame arrives) by using .invalid, resolved at finish.
    chapters.withLock { state in
      let time = state.lastPresentationTime.isValid ? state.lastPresentationTime : state.firstPresentationTime
      state.pendingChapters.append(ChapterTrackMuxer.Marker(time: time, text: text))
    }
  }

  /// Finalize the file: mark the inputs finished and await `finishWriting`. Call once, after the
  /// encoder has flushed all pending frames. A no-op if no frame was ever written.
  func finish() async throws {
    guard let assetWriter, let input else {
      logger.log("SimulatorVideoFileWriter.finish called with no frames written; nothing to finalize")
      return
    }
    input.markAsFinished()
    await assetWriter.finishWriting()
    if assetWriter.status == .failed {
      throw SimulatorVideoFileWriterError.assetWriterFailedToFinish(errorDescription: assetWriter.error.map { String(describing: $0) } ?? "unknown error")
    }
    let (markers, sessionStart, videoEnd) = chapters.withLock { ($0.pendingChapters, $0.firstPresentationTime, $0.lastPresentationTime) }
    if chaptersEnabled && !markers.isEmpty {
      try await ChapterTrackMuxer.addChapters(markers, sessionStart: sessionStart, videoEnd: videoEnd, to: outputURL, fileType: fileType, logger: logger)
    }
  }

  // MARK: - Private

  private func recordVideoPosition(_ time: CMTime) {
    chapters.withLock { state in
      if !state.firstPresentationTime.isValid {
        state.firstPresentationTime = time
      }
      state.lastPresentationTime = time
    }
  }

  private func startIfNeeded(with sampleBuffer: CMSampleBuffer) throws -> AVAssetWriterInput {
    if let input {
      return input
    }
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      throw SimulatorVideoFileWriterError.firstSampleBufferMissingFormatDescription
    }
    // AVAssetWriter refuses to overwrite an existing file.
    try? FileManager.default.removeItem(at: outputURL)

    let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
    assetWriter.movieFragmentInterval = Self.movieFragmentInterval
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
    input.expectsMediaDataInRealTime = true
    guard assetWriter.canAdd(input) else {
      throw SimulatorVideoFileWriterError.cannotAddVideoInput
    }
    assetWriter.add(input)

    guard assetWriter.startWriting() else {
      throw SimulatorVideoFileWriterError.assetWriterFailedToStart(errorDescription: assetWriter.error.map { String(describing: $0) } ?? "unknown error")
    }
    let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    assetWriter.startSession(atSourceTime: start)
    anchor.withLock { $0 = start }
    self.assetWriter = assetWriter
    self.input = input
    return input
  }
}
