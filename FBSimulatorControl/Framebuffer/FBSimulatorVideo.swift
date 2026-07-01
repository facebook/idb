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
/// encoded frames into an `.mp4` via `FBVideoFileWriter` (`AVAssetWriter`). The byte-stream consumer is
/// a discard; only the `.mp4` is produced.
// @unchecked Sendable: an in-process recording operation handle, used across async boundaries by the
// recording commands and the sime2e record path. All mutable state is confined to its serial `queue`
// (and `hasStopped` guards the single stop), and its `stream`/`fileWriter` are themselves
// `@unchecked Sendable`, matching the sibling `FBSimulatorVideoStream`.
@objc(FBSimulatorVideo)
public class FBSimulatorVideo: NSObject, @unchecked Sendable {

  // MARK: - Properties

  private let queue: DispatchQueue
  /// The underlying encode pipeline. Exposed so the sime2e record path can drive stdin-controlled
  /// overlay/chapter/screenshot on the live stream, mirroring how `videoStream(...)` returns the stream.
  public let stream: FBSimulatorVideoStream
  private let fileWriter: FBVideoFileWriter
  private var hasStopped = false

  // MARK: - Initializers

  public class func video(withFramebuffer framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, filePath: String, edgeInsets: FBVideoStreamEdgeInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), chaptersEnabled: Bool = false, logger: any FBControlCoreLogger) -> FBSimulatorVideo {
    FBSimulatorVideo(framebuffer: framebuffer, configuration: configuration, filePath: filePath, edgeInsets: edgeInsets, chaptersEnabled: chaptersEnabled, logger: logger)
  }

  private init(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, filePath: String, edgeInsets: FBVideoStreamEdgeInsets, chaptersEnabled: Bool, logger: any FBControlCoreLogger) {
    self.queue = DispatchQueue(label: "com.facebook.simulatorvideo")
    let fileWriter = FBVideoFileWriter(filePath: filePath, chaptersEnabled: chaptersEnabled, logger: logger)
    self.fileWriter = fileWriter
    self.stream = FBSimulatorVideoStream.makeRecorder(framebuffer: framebuffer, configuration: configuration, edgeInsets: edgeInsets, fileWriter: fileWriter, logger: logger)
    super.init()
  }

  // MARK: - Recording

  public func startRecording() async throws {
    // Encoded frames are routed to `fileWriter` (which opens lazily on its first sample, since
    // passthrough muxing needs that sample's format); the stream's byte consumer is unused, so a
    // no-op consumer satisfies its streaming bookkeeping (and never reports back-pressure).
    try await bridgeFBFutureVoid(stream.startStreaming(FBNullDataConsumer()))
  }

  public func stopRecording() async throws {
    if hasStopped {
      return
    }
    hasStopped = true
    // Stop the framebuffer push and flush the encoder (tearDown's VTCompressionSessionCompleteFrames
    // drains all pending frames into `fileWriter`) before finalizing the file's moov.
    try await bridgeFBFutureVoid(stream.stopStreaming())
    try await fileWriter.finish()
  }
}
