/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
@preconcurrency import FBControlCore
import Foundation

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
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    if video != nil {
      throw FBDeviceControlError().describe("Cannot create a new video recording session, one is already active").build()
    }
    let video = try await FBDeviceVideo.videoAsync(for: device, filePath: filePath)
    self.video = video
    try await bridgeFBFutureVoid(video.startRecording())
    return CommandVideoRecording {
      return try await self.stopRecordingAsync()
    }
  }

  fileprivate func stopRecordingAsync() async throws -> URL {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    guard let video else {
      throw FBDeviceControlError().describe("There was no existing video instance for \(device)").build()
    }
    self.video = nil
    try await bridgeFBFutureVoid(video.stopRecording())
    return video.outputURL
  }

  fileprivate func createStreamAsync(with configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    guard let device, let logger = device.logger else {
      throw FBDeviceControlError().describe("Device is nil").build()
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

private final class CommandVideoRecording: FBVideoRecording {
  private let stopRecording: () async throws -> URL

  init(stopRecording: @escaping () async throws -> URL) {
    self.stopRecording = stopRecording
  }

  func stop() async throws -> URL {
    try await stopRecording()
  }
}

// MARK: - FBDevice+VideoStreamCommands

extension FBDevice: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    try await videoRecordingCommands().createStreamAsync(with: configuration, to: consumer)
  }
}
