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
  }

  /// The Unix timestamp of the recording's own media time zero, or nil before a frame was muxed.
  ///
  /// The file's timeline is anchored at the first encoded sample's presentation timestamp, and the
  /// encoder stamps presentation timestamps as an offset from `systemUptime` at the first pushed
  /// frame, so media zero is `timeAtFirstFrame + anchor` on the uptime clock. Uptime and wall clock
  /// are read as one adjacent pair and differenced, which keeps the answer right however long the
  /// recording ran or finalization took. Callers measuring their own wall-clock events against the
  /// recording need this rather than the moment they observed the recorder come up, which trails
  /// media zero by however long readiness took to detect.
  public func startedAt() async -> Double? {
    guard let anchor = fileWriter.startPresentationTime else {
      return nil
    }
    let timeAtFirstFrame = await stream.currentTimeAtFirstFrame
    guard timeAtFirstFrame > 0 else {
      return nil
    }
    let uptime = ProcessInfo.processInfo.systemUptime
    let wallClock = Date().timeIntervalSince1970
    return wallClock - (uptime - (timeAtFirstFrame + anchor.seconds))
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
