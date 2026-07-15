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

private enum FBDeviceVideoError: Error {
  case failedToEnableScreenCaptureDevices(status: OSStatus)
  case timedOutWaitingForCaptureDevice(timeout: TimeInterval, deviceDescription: String)
  case cannotAddDeviceInput(captureDeviceDescription: String)
}

extension FBDeviceVideoError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .failedToEnableScreenCaptureDevices(let status):
      return "Failed to enable Screen Capture devices with status \(status)"
    case let .timedOutWaitingForCaptureDevice(timeout, deviceDescription):
      return "Timed out waiting \(timeout)s for device \(deviceDescription) to have an associated capture device appear"
    case .cannotAddDeviceInput(let captureDeviceDescription):
      return "Cannot add Device Input to session for \(captureDeviceDescription)"
    }
  }
}

public final class FBDeviceVideo {
  private let encoder: FBVideoFileWriter

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
      throw FBDeviceVideoError.failedToEnableScreenCaptureDevices(status: status)
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
        throw FBDeviceVideoError.timedOutWaitingForCaptureDevice(timeout: timeout, deviceDescription: "\(device)")
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  // MARK: Initializers

  public class func captureSessionAsync(for device: FBDevice) async throws -> AVCaptureSession {
    try allowAccessToScreenCaptureDevices()
    let captureDevice = try await findCaptureDeviceAsync(for: device)
    let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
    let session = AVCaptureSession()
    if !session.canAddInput(deviceInput) {
      throw FBDeviceVideoError.cannotAddDeviceInput(captureDeviceDescription: "\(captureDevice)")
    }
    session.addInput(deviceInput)
    return session
  }

  public class func videoAsync(for device: FBDevice, filePath: String) async throws -> FBDeviceVideo {
    let session = try await captureSessionAsync(for: device)
    let encoder = try FBVideoFileWriter.writer(withSession: session, filePath: filePath, logger: device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger)
    return FBDeviceVideo(encoder: encoder)
  }

  private init(encoder: FBVideoFileWriter) {
    self.encoder = encoder
  }

  // MARK: Public

  public func startRecording() async throws {
    try await encoder.start()
  }

  public func stop() async throws -> URL {
    try await encoder.stop()
  }

}
