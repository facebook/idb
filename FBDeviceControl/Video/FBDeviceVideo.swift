/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMediaIO
@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceVideo)
public class FBDeviceVideo: NSObject, FBiOSTargetOperation {
  private let encoder: FBVideoFileWriter
  private let workQueue: DispatchQueue

  // MARK: Initialization Helpers

  private class func allowAccessToScreenCaptureDevices() throws {
    var properties = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var allow: UInt32 = 1
    let status = CMIOObjectSetPropertyData(
      CMIOObjectID(kCMIOObjectSystemObject),
      &properties,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &allow
    )
    if status != 0 {
      throw FBDeviceControlError.describe("Failed to enable Screen Capture devices with status \(status)").build()
    }
  }

  private class func findCaptureDeviceAsync(for device: FBDevice) async throws -> AVCaptureDevice {
    let timeout = FBControlCoreGlobalConfiguration.fastTimeout
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      if let captureDevice = AVCaptureDevice(uniqueID: device.udid) {
        return captureDevice
      }
      if Date() >= deadline {
        throw FBDeviceControlError.describe("Timed out waiting \(timeout)s for device \(device) to have an associated capture device appear").build()
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  // MARK: Initializers

  @objc(captureSessionForDevice:)
  public class func captureSession(for device: FBDevice) -> FBFuture<AVCaptureSession> {
    fbFutureFromAsync {
      try await captureSessionAsync(for: device)
    }
  }

  public class func captureSessionAsync(for device: FBDevice) async throws -> AVCaptureSession {
    try allowAccessToScreenCaptureDevices()
    let captureDevice = try await findCaptureDeviceAsync(for: device)
    let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
    let session = AVCaptureSession()
    if !session.canAddInput(deviceInput) {
      throw FBDeviceControlError.describe("Cannot add Device Input to session for \(captureDevice)").build()
    }
    session.addInput(deviceInput)
    return session
  }

  @objc(videoForDevice:filePath:)
  public class func video(for device: FBDevice, filePath: String) -> FBFuture<FBDeviceVideo> {
    fbFutureFromAsync {
      try await videoAsync(for: device, filePath: filePath)
    }
  }

  public class func videoAsync(for device: FBDevice, filePath: String) async throws -> FBDeviceVideo {
    let session = try await captureSessionAsync(for: device)
    let encoder = try FBVideoFileWriter.writer(withSession: session, filePath: filePath, logger: device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger)
    return FBDeviceVideo(encoder: encoder, workQueue: device.workQueue)
  }

  private init(encoder: FBVideoFileWriter, workQueue: DispatchQueue) {
    self.encoder = encoder
    self.workQueue = workQueue
    super.init()
  }

  // MARK: Public

  @objc public func startRecording() -> FBFuture<NSNull> {
    return encoder.startRecording()
  }

  @objc public func stopRecording() -> FBFuture<NSNull> {
    return encoder.stopRecording()
  }

  // MARK: FBiOSTargetOperation

  @objc public var completed: FBFuture<NSNull> {
    let encoder = self.encoder
    return encoder.completed().onQueue(
      workQueue,
      respondToCancellation: {
        return encoder.stopRecording()
      })
  }
}
