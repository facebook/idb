/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private enum SimulatorVideoRecordingCommandError: Error {
  case recordingAlreadyActive
  case missingVideo(simulatorDescription: String)
}

extension SimulatorVideoRecordingCommandError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .recordingAlreadyActive:
      return "Cannot create a new video recording session, one is already active"
    case .missingVideo(let simulatorDescription):
      return "There was no existing video instance for \(simulatorDescription)"
    }
  }
}

public final class FBSimulatorVideoRecordingCommands: VideoRecordingCommands {

  private weak var simulator: FBSimulator?
  private var video: FBSimulatorVideo?

  public class func commands(with simulator: FBSimulator) -> FBSimulatorVideoRecordingCommands {
    FBSimulatorVideoRecordingCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  /// The default configuration for in-process recording when the caller supplies none: H264 at a
  /// constant frame rate (eager cadence), clean frames, default quality. The transport is irrelevant —
  /// recording muxes encoded samples to a file rather than byte-framing them.
  /// `RecordMethodHandler` mirrors the frame rate here as the meaning of an unset `fps` on the wire.
  private static var recordingConfiguration: FBVideoStreamConfiguration {
    FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: 30,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil)
  }

  /// Simulator recording goes through `FBSimulatorVideo`, which reads the configuration it is
  /// handed rather than imposing a fixed one.
  public var honorsRecordingConfiguration: Bool { true }

  public func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    try await startRecording(toFile: filePath, configuration: Self.recordingConfiguration)
  }

  public func startRecording(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws -> any FBVideoRecording {
    guard let simulator = self.simulator else {
      throw WeakTargetError.simulator
    }
    if video != nil {
      throw SimulatorVideoRecordingCommandError.recordingAlreadyActive
    }
    let framebuffer = try await simulator.lifecycle.connectToFramebuffer()
    let video = FBSimulatorVideo.video(withFramebuffer: framebuffer, configuration: configuration, filePath: filePath, logger: simulator.logger)
    try await video.startRecording()
    self.video = video
    return VideoRecordingHandle {
      return try await self.stop()
    }
  }

  public func stop() async throws -> URL {
    let video = self.video
    self.video = nil
    guard let video else {
      throw SimulatorVideoRecordingCommandError.missingVideo(simulatorDescription: self.simulator?.description ?? "unknown")
    }
    return try await video.stop()
  }
}
