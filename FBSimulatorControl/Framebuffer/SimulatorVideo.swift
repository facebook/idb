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

  public static func video(withFramebuffer framebuffer: Framebuffer, configuration: FBVideoStreamConfiguration, filePath: String, fileType: AVFileType = .mp4, edgeInsets: VideoStreamEdgeInsets = VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), chaptersEnabled: Bool = false, logger: any FBControlCoreLogger) -> SimulatorVideo {
    SimulatorVideo(framebuffer: framebuffer, configuration: configuration, filePath: filePath, fileType: fileType, edgeInsets: edgeInsets, chaptersEnabled: chaptersEnabled, logger: logger)
  }

  private init(framebuffer: Framebuffer, configuration: FBVideoStreamConfiguration, filePath: String, fileType: AVFileType, edgeInsets: VideoStreamEdgeInsets, chaptersEnabled: Bool, logger: any FBControlCoreLogger) {
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
  }

  public func stop() async throws -> URL {
    if hasStopped {
      return outputURL
    }
    hasStopped = true
    // Stop the framebuffer push and flush the encoder (tearDown's VTCompressionSessionCompleteFrames
    // drains all pending frames into `fileWriter`) before finalizing the file's moov.
    try await stream.stopStreaming()
    try await fileWriter.finish()
    return outputURL
  }

}
