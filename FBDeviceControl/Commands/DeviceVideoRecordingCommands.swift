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

public final class DeviceVideoRecordingCommands: VideoRecordingCommands {
  private weak var device: Device?
  private var video: DeviceVideo?

  public class func commands(with device: Device) -> DeviceVideoRecordingCommands {
    DeviceVideoRecordingCommands(device: device)
  }

  init(device: Device) {
    self.device = device
  }

  // MARK: - Async

  public func start(toFile filePath: String) async throws -> any VideoRecording {
    guard let device else {
      throw DeviceVideoRecordingCommandError.missingDevice
    }
    if video != nil {
      throw DeviceVideoRecordingCommandError.recordingAlreadyActive
    }
    let video = try await DeviceVideo.video(for: device, filePath: filePath)
    self.video = video
    try await video.startRecording()
    return VideoRecordingHandle {
      return try await self.stop()
    }
  }

  private func stop() async throws -> URL {
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
