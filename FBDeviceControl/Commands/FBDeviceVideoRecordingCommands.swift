/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
@preconcurrency import FBControlCore
import Foundation

private enum FBDeviceVideoRecordingCommandError: Error {
  case missingDevice
  case recordingAlreadyActive
  case missingVideo(deviceDescription: String)
}

extension FBDeviceVideoRecordingCommandError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .missingDevice:
      return "Device is nil"
    case .recordingAlreadyActive:
      return "Cannot create a new video recording session, one is already active"
    case .missingVideo(let deviceDescription):
      return "There was no existing video instance for \(deviceDescription)"
    }
  }
}

public class FBDeviceVideoRecordingCommands: NSObject, FBiOSTargetCommand {
  private weak var device: FBDevice?
  private var video: FBDeviceVideo?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    // swiftlint:disable:next force_cast
    self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - Async

  fileprivate func startRecordingAsync(toFile filePath: String) async throws -> any FBVideoRecording {
    guard let device else {
      throw FBDeviceVideoRecordingCommandError.missingDevice
    }
    if video != nil {
      throw FBDeviceVideoRecordingCommandError.recordingAlreadyActive
    }
    let video = try await FBDeviceVideo.videoAsync(for: device, filePath: filePath)
    self.video = video
    try await video.startRecording()
    return FBVideoRecordingHandle {
      return try await self.stopAsync()
    }
  }

  fileprivate func stopAsync() async throws -> URL {
    guard let device else {
      throw FBDeviceVideoRecordingCommandError.missingDevice
    }
    guard let video else {
      throw FBDeviceVideoRecordingCommandError.missingVideo(deviceDescription: "\(device)")
    }
    self.video = nil
    return try await video.stop()
  }

  fileprivate func createStreamAsync(with configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    guard let device, let logger = device.logger else {
      throw FBDeviceVideoRecordingCommandError.missingDevice
    }
    let session = try await FBDeviceVideo.captureSessionAsync(for: device)
    let stream = try FBDeviceVideoStream.stream(withSession: session, configuration: configuration, logger: logger)
    try await stream.startStreaming(consumer)
    return stream
  }
}

// MARK: - FBDevice+VideoRecordingCommands

extension FBDevice: VideoRecordingCommands {

  public func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    try await videoRecordingCommands().startRecordingAsync(toFile: filePath)
  }
}

// MARK: - FBDevice+VideoStreamCommands

extension FBDevice: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    try await videoRecordingCommands().createStreamAsync(with: configuration, to: consumer)
  }
}
