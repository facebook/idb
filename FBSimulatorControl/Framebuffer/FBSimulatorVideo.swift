/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - FBSimulatorVideo

/// Records simulator video in-process. Drives the framebuffer through the shared
/// `FBSimulatorVideoStream` encode pipeline at an eager (constant-frame-rate) cadence and muxes the
/// encoded frames into an `.mp4` via `FBSimulatorVideoFileWriter` (`AVAssetWriter`). The byte-stream consumer is
/// a discard; only the `.mp4` is produced.
///
/// An actor: `hasStopped` guards the single stop and is set before the first suspension, so
/// concurrent `stop()` calls cannot both finalize.
public actor FBSimulatorVideo {

  // MARK: - Properties

  /// The URL of the `.mp4` this recording writes.
  let outputURL: URL
  /// The underlying encode pipeline. Exposed so the sime2e record path can drive stdin-controlled
  /// overlay/chapter/screenshot on the live stream, mirroring how `videoStream(...)` returns the
  /// stream. `nonisolated`: a constant of Sendable (actor) type, readable cross-module without a hop.
  public nonisolated let stream: FBSimulatorVideoStream
  private let fileWriter: FBSimulatorVideoFileWriter
  private var hasStopped = false

  // MARK: - Initializers

  public static func video(withFramebuffer framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, filePath: String, edgeInsets: FBVideoStreamEdgeInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), chaptersEnabled: Bool = false, logger: any FBControlCoreLogger) -> FBSimulatorVideo {
    FBSimulatorVideo(framebuffer: framebuffer, configuration: configuration, filePath: filePath, edgeInsets: edgeInsets, chaptersEnabled: chaptersEnabled, logger: logger)
  }

  private init(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, filePath: String, edgeInsets: FBVideoStreamEdgeInsets, chaptersEnabled: Bool, logger: any FBControlCoreLogger) {
    self.outputURL = URL(fileURLWithPath: filePath)
    let fileWriter = FBSimulatorVideoFileWriter(filePath: filePath, chaptersEnabled: chaptersEnabled, logger: logger)
    self.fileWriter = fileWriter
    self.stream = FBSimulatorVideoStream.makeRecorder(framebuffer: framebuffer, configuration: configuration, edgeInsets: edgeInsets, fileWriter: fileWriter, logger: logger)
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
