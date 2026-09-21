/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import FBControlCore
import Foundation

/// Records simulator video in-process. Drives the framebuffer through the shared
/// `SimulatorVideoStream` encode pipeline with the configured cadence and muxes encoded frames
/// into MP4 or MOV via `SimulatorVideoFileWriter` (`AVAssetWriter`).
/// The byte-stream consumer is unused; only the recording file is produced.
///
/// An actor: `hasStopped` guards the single stop and is set before the first suspension, so
/// concurrent `stop()` calls cannot both finalize.
public actor SimulatorVideo {

  /// The URL of the recording file.
  let outputURL: URL
  /// The underlying encode pipeline, exposed so callers can drive overlay/chapter/screenshot on the live
  /// recording. `nonisolated`: a constant of Sendable (actor) type, readable without a hop.
  public nonisolated let stream: SimulatorVideoStream
  private let fileWriter: SimulatorVideoFileWriter
  private var hasStopped = false
  private var keyFrames: Task<Void, Never>?

  /// How often the recording asks the encoder for a keyframe, at half the writer's fragment
  /// interval so that a sync sample always falls between two fragment boundaries.
  ///
  /// A fragmented movie can only begin a fragment at a sync sample, and the encoder's keyframe
  /// interval is a maximum in *source* duration: it can only be honoured on a frame, and the
  /// simulator's screen supplies frames only as it changes. A screen that sits still through a slow
  /// step stretches the gap between sync samples far past the nominal interval -- twelve seconds
  /// against a nominal four, measured on a recording of the end-to-end suite -- and a fragment
  /// boundary landing in that gap is refused, ending the recording. The request pushes a frame of
  /// its own, so the gap is bounded by this interval whatever the screen is doing.
  private static let keyFrameInterval = Duration.seconds(SimulatorVideoFileWriter.movieFragmentInterval.seconds / 2)

  public static func video(withFramebuffer framebuffer: Framebuffer, configuration: VideoStreamConfiguration, filePath: String, fileType: AVFileType = .mp4, edgeInsets: VideoStreamEdgeInsets = VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), chaptersEnabled: Bool = false, logger: any ControlCoreLogger) -> SimulatorVideo {
    SimulatorVideo(framebuffer: framebuffer, configuration: configuration, filePath: filePath, fileType: fileType, edgeInsets: edgeInsets, chaptersEnabled: chaptersEnabled, logger: logger)
  }

  private init(framebuffer: Framebuffer, configuration: VideoStreamConfiguration, filePath: String, fileType: AVFileType, edgeInsets: VideoStreamEdgeInsets, chaptersEnabled: Bool, logger: any ControlCoreLogger) {
    self.outputURL = URL(fileURLWithPath: filePath)
    let fileWriter = SimulatorVideoFileWriter(filePath: filePath, fileType: fileType, chaptersEnabled: chaptersEnabled, logger: logger)
    self.fileWriter = fileWriter
    self.stream = SimulatorVideoStream.makeRecorder(framebuffer: framebuffer, configuration: configuration, edgeInsets: edgeInsets, fileWriter: fileWriter, logger: logger)
  }

  // MARK: - Recording

  public func startRecording() async throws {
    // Encoded frames are routed to `fileWriter` (which opens lazily on its first sample, since
    // passthrough muxing needs that sample's format); the stream's byte consumer is unused, so a
    // no-op consumer satisfies its streaming bookkeeping (and never reports back-pressure).
    try await stream.startStreaming(FBNullDataConsumer())
    keyFrames = Task { [stream] in
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.keyFrameInterval)
        guard !Task.isCancelled else { return }
        stream.requestKeyFrame()
      }
    }
  }

  /// The Unix timestamp of the recording's own media time zero, or nil before a frame was muxed.
  ///
  /// The file's timeline is anchored at the first encoded sample's presentation timestamp, which
  /// the encoder stamps relative to the first pushed frame, so media zero is that frame plus the
  /// anchor. When the frame was captured is the wall clock read as it was pushed, so the answer is
  /// unchanged by how long the recording ran, by how long finalization took, and by the clock
  /// being set in between. Callers measuring their own wall-clock events against the recording
  /// need this rather than the moment they observed the recorder come up, which trails media zero
  /// by however long readiness took to detect.
  public func startedAt() async -> Double? {
    guard let anchor = fileWriter.startPresentationTime else {
      return nil
    }
    return await stream.mediaOrigin(anchor: anchor.seconds)
  }

  public func stop() async throws -> URL {
    if hasStopped {
      return outputURL
    }
    hasStopped = true
    keyFrames?.cancel()
    keyFrames = nil
    // Stop the framebuffer push and flush the encoder (tearDown's VTCompressionSessionCompleteFrames
    // drains all pending frames into `fileWriter`) before finalizing the file's moov.
    try await stream.stopStreaming()
    try await fileWriter.finish()
    return outputURL
  }

}
