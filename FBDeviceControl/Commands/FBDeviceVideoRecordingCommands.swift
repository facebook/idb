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
    self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - Async

  fileprivate func startRecordingAsync(toFile filePath: String) async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    if video != nil {
      throw FBDeviceControlError().describe("Cannot create a new video recording session, one is already active").build()
    }
    let video = try await FBDeviceVideo.videoAsync(for: device, filePath: filePath)
    self.video = video
    try await bridgeFBFutureVoid(video.startRecording())
  }

  fileprivate func stopRecordingAsync() async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    guard let video else {
      throw FBDeviceControlError().describe("There was no existing video instance for \(device)").build()
    }
    self.video = nil
    try await bridgeFBFutureVoid(video.stopRecording())
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

  public func startRecording(toFile filePath: String) async throws {
    try await videoRecordingCommands().startRecordingAsync(toFile: filePath)
  }

  public func stopRecording() async throws {
    try await videoRecordingCommands().stopRecordingAsync()
  }
}

// MARK: - FBDevice+VideoStreamCommands

extension FBDevice: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    try await videoRecordingCommands().createStreamAsync(with: configuration, to: consumer)
  }
}
