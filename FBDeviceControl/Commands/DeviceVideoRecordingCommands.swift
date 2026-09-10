/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
@preconcurrency import FBControlCore
import Foundation

private enum DeviceVideoRecordingCommandError: Error {
  case missingDevice
  case recordingAlreadyActive
  case missingVideo(deviceDescription: String)
}

extension DeviceVideoRecordingCommandError: LocalizedError {
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

public final class DeviceVideoRecordingCommands {
  private weak var device: FBDevice?
  private var video: DeviceVideo?

  public class func commands(with device: FBDevice) -> DeviceVideoRecordingCommands {
    DeviceVideoRecordingCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Async

  fileprivate func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    guard let device else {
      throw DeviceVideoRecordingCommandError.missingDevice
    }
    if video != nil {
      throw DeviceVideoRecordingCommandError.recordingAlreadyActive
    }
    let video = try await DeviceVideo.video(for: device, filePath: filePath)
    self.video = video
    try await video.startRecording()
    return FBVideoRecordingHandle {
      return try await self.stop()
    }
  }

  fileprivate func stop() async throws -> URL {
    guard let device else {
      throw DeviceVideoRecordingCommandError.missingDevice
    }
    guard let video else {
      throw DeviceVideoRecordingCommandError.missingVideo(deviceDescription: "\(device)")
    }
    self.video = nil
    return try await video.stop()
  }
}

// MARK: - FBDevice+VideoRecordingCommands

extension FBDevice: VideoRecordingCommands {

  public func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    try await videoRecording.startRecording(toFile: filePath)
  }
}
