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

private enum DeviceVideoError: Error {
  case failedToEnableScreenCaptureDevices(status: OSStatus)
  case timedOutWaitingForCaptureDevice(timeout: TimeInterval, deviceDescription: String)
  case cannotAddDeviceInput(captureDeviceDescription: String)
}

extension DeviceVideoError: LocalizedError {
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

public final class DeviceVideo {
  private let encoder: VideoFileWriter

  // MARK: - Initialization Helpers

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
      throw DeviceVideoError.failedToEnableScreenCaptureDevices(status: status)
    }
  }

  private class func findCaptureDevice(for device: FBDevice) async throws -> AVCaptureDevice {
    let timeout = FBControlCoreGlobalConfiguration.fastTimeout
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      if let captureDevice = AVCaptureDevice(uniqueID: device.udid) {
        return captureDevice
      }
      if Date() >= deadline {
        throw DeviceVideoError.timedOutWaitingForCaptureDevice(timeout: timeout, deviceDescription: "\(device)")
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  public class func captureSession(for device: FBDevice) async throws -> AVCaptureSession {
    try allowAccessToScreenCaptureDevices()
    let captureDevice = try await findCaptureDevice(for: device)
    let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
    let session = AVCaptureSession()
    if !session.canAddInput(deviceInput) {
      throw DeviceVideoError.cannotAddDeviceInput(captureDeviceDescription: "\(captureDevice)")
    }
    session.addInput(deviceInput)
    return session
  }

  public class func video(for device: FBDevice, filePath: String) async throws -> DeviceVideo {
    let session = try await captureSession(for: device)
    let encoder = try VideoFileWriter.writer(withSession: session, filePath: filePath, logger: device.logger)
    return DeviceVideo(encoder: encoder)
  }

  private init(encoder: VideoFileWriter) {
    self.encoder = encoder
  }

  public func startRecording() async throws {
    try await encoder.start()
  }

  public func stop() async throws -> URL {
    try await encoder.stop()
  }

}
