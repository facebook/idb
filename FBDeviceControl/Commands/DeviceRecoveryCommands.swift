/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public enum FBDeviceRecoveryError: Error {
  case callUnavailable(function: String)
  case enterRecoveryFailed(message: String)
  case notInRecovery(deviceDescription: String)
  case autoBootFailed(recoveryDevice: String, message: String)
  case exitRecoveryFailed(recoveryDevice: String, message: String)
}

extension FBDeviceRecoveryError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .callUnavailable(function):
      return "\(function) function not available"
    case let .enterRecoveryFailed(message):
      return "Failed have device enter recovery \(message)"
    case let .notInRecovery(deviceDescription):
      return "Device \(deviceDescription) is not in recovery mode"
    case let .autoBootFailed(recoveryDevice, message):
      return "Failed to set autoboot for recovery device \(recoveryDevice) \(message)"
    case let .exitRecoveryFailed(recoveryDevice, message):
      return "Failed have device \(recoveryDevice) exit recovery \(message)"
    }
  }
}

public final class FBDeviceRecoveryCommands {
  private(set) weak var device: FBDevice?

  public class func commands(with device: FBDevice) -> FBDeviceRecoveryCommands {
    FBDeviceRecoveryCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Recovery

  fileprivate func enterRecovery() async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    try await device.withConnectedDevice(purpose: "enter_recovery") { connectedDevice in
      guard let enterRecoveryFunc = connectedDevice.calls.EnterRecovery else {
        throw FBDeviceRecoveryError.callUnavailable(function: "EnterRecovery")
      }
      let status = enterRecoveryFunc(connectedDevice.amDeviceRef)
      if status != 0 {
        throw FBDeviceRecoveryError.enterRecoveryFailed(message: Self.errorMessage(for: status, calls: connectedDevice.calls))
      }
    }
  }

  fileprivate func exitRecovery() async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    guard let recoveryDevice = device.recoveryModeDeviceRef else {
      throw FBDeviceRecoveryError.notInRecovery(deviceDescription: String(describing: device))
    }
    guard let setAutoBootFunc = device.calls.RecoveryModeDeviceSetAutoBoot else {
      throw FBDeviceRecoveryError.callUnavailable(function: "RecoveryModeDeviceSetAutoBoot")
    }
    var status = setAutoBootFunc(recoveryDevice, 1)
    if status != 0 {
      throw FBDeviceRecoveryError.autoBootFailed(recoveryDevice: String(describing: recoveryDevice), message: Self.errorMessage(for: status, calls: device.calls))
    }
    guard let rebootFunc = device.calls.RecoveryDeviceReboot else {
      throw FBDeviceRecoveryError.callUnavailable(function: "RecoveryDeviceReboot")
    }
    status = rebootFunc(recoveryDevice)
    if status != 0 {
      throw FBDeviceRecoveryError.exitRecoveryFailed(recoveryDevice: String(describing: recoveryDevice), message: Self.errorMessage(for: status, calls: device.calls))
    }
  }

  private static func errorMessage(for status: Int32, calls: AMDCalls) -> String {
    if let copyErrorTextFunc = calls.CopyErrorText {
      return copyErrorTextFunc(status)?.takeRetainedValue() as String? ?? "Unknown error"
    }
    return "Unknown error"
  }
}

// MARK: - FBDevice+RecoveryCommands

extension FBDevice: RecoveryCommands {

  public func enterRecovery() async throws {
    try await recovery.enterRecovery()
  }

  public func exitRecovery() async throws {
    try await recovery.exitRecovery()
  }
}
