/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceVideoRecordingCommands)
public class FBDeviceVideoRecordingCommands: NSObject, FBVideoRecordingCommands, FBVideoStreamCommands {
  private weak var device: FBDevice?
  private var video: FBDeviceVideo?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBVideoRecordingCommands (legacy FBFuture entry points)

  public func startRecording(toFile filePath: String) -> FBFuture<any FBiOSTargetOperation> {
    fbFutureFromAsync { [self] in
      try await startRecordingAsync(toFile: filePath) as any FBiOSTargetOperation
    }
  }

  public func stopRecording() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await stopRecordingAsync()
      return NSNull()
    }
  }

  // MARK: - FBVideoStreamCommands (legacy FBFuture entry point)

  public func createStream(with configuration: FBVideoStreamConfiguration) -> FBFuture<any FBVideoStream> {
    fbFutureFromAsync { [self] in
      try await createStreamAsync(with: configuration)
    }
  }

  // MARK: - Async

  fileprivate func startRecordingAsync(toFile filePath: String) async throws -> FBDeviceVideo {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    if video != nil {
      throw FBDeviceControlError().describe("Cannot create a new video recording session, one is already active").build()
    }
    let video = try await FBDeviceVideo.videoAsync(for: device, filePath: filePath)
    self.video = video
    try await bridgeFBFutureVoid(video.startRecording())
    return video
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

  fileprivate func createStreamAsync(with configuration: FBVideoStreamConfiguration) async throws -> any FBVideoStream {
    guard let device, let logger = device.logger else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let session = try await FBDeviceVideo.captureSessionAsync(for: device)
    return try FBDeviceVideoStream.stream(withSession: session, configuration: configuration, logger: logger)
  }
}
