/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// swiftlint:disable force_cast force_unwrapping

private enum FBSimulatorVideoRecordingCommandError: Error {
  case recordingAlreadyActive
  case missingVideo(simulatorDescription: String)
}

extension FBSimulatorVideoRecordingCommandError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .recordingAlreadyActive:
      return "Cannot create a new video recording session, one is already active"
    case .missingVideo(let simulatorDescription):
      return "There was no existing video instance for \(simulatorDescription)"
    }
  }
}

public final class FBSimulatorVideoRecordingCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var video: FBSimulatorVideo?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> FBSimulatorVideoRecordingCommands {
    FBSimulatorVideoRecordingCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Private

  /// The default configuration for in-process recording when the caller supplies none: H264 at a
  /// constant frame rate (eager cadence), clean frames, default quality. The transport is irrelevant —
  /// recording muxes encoded samples to a file rather than byte-framing them.
  private static var recordingConfiguration: FBVideoStreamConfiguration {
    FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: 30,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil)
  }

  fileprivate func startRecordingAsync(toFile filePath: String) async throws -> any FBVideoRecording {
    try await startRecordingAsync(toFile: filePath, configuration: Self.recordingConfiguration)
  }

  fileprivate func startRecordingAsync(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws -> any FBVideoRecording {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    if video != nil {
      throw FBSimulatorVideoRecordingCommandError.recordingAlreadyActive
    }
    let framebuffer = try await simulator.connectToFramebuffer()
    let video = FBSimulatorVideo.video(withFramebuffer: framebuffer, configuration: configuration, filePath: filePath, logger: simulator.logger!)
    try await video.startRecording()
    self.video = video
    return FBVideoRecordingHandle {
      return try await self.stopAsync()
    }
  }

  fileprivate func stopAsync() async throws -> URL {
    let video = self.video
    self.video = nil
    guard let video else {
      throw FBSimulatorVideoRecordingCommandError.missingVideo(simulatorDescription: self.simulator?.description ?? "unknown")
    }
    return try await video.stop()
  }

  fileprivate func createStreamAsync(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let logger = simulator.logger
    let framebuffer = try await simulator.connectToFramebuffer()
    return try await FBSimulatorVideoStream.start(framebuffer: framebuffer, configuration: configuration, to: consumer, logger: logger!)
  }
}

// MARK: - FBSimulator+VideoRecordingCommands

extension FBSimulator: VideoRecordingCommands {

  public func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    try await videoRecordingCommands().startRecordingAsync(toFile: filePath)
  }

  public func startRecording(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws -> any FBVideoRecording {
    try await videoRecordingCommands().startRecordingAsync(toFile: filePath, configuration: configuration)
  }
}

// MARK: - FBSimulator+VideoStreamCommands

extension FBSimulator: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    try await videoRecordingCommands().createStreamAsync(configuration: configuration, to: consumer)
  }
}
