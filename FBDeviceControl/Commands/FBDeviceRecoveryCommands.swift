/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceRecoveryCommands)
public class FBDeviceRecoveryCommands: NSObject, FBiOSTargetCommand {
  private(set) weak var device: FBDevice?

  // MARK: Initializers

  @objc
  public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBDeviceRecoveryCommands(device: target as! FBDevice), to: self)
  }

  init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: FBDeviceRecoveryCommands (legacy FBFuture entry points)

  @objc
  public func enterRecovery() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await enterRecoveryAsync()
      return NSNull()
    }
  }

  @objc
  public func exitRecovery() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await exitRecoveryAsync()
      return NSNull()
    }
  }

  // MARK: - Async

  fileprivate func enterRecoveryAsync() async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    try await withFBFutureContext(device.connectToDevice(withPurpose: "enter_recovery")) { connectedDevice in
      guard let enterRecoveryFunc = connectedDevice.calls.EnterRecovery else {
        throw FBDeviceControlError.describe("EnterRecovery function not available").build()
      }
      let status = enterRecoveryFunc(connectedDevice.amDeviceRef)
      if status != 0 {
        throw FBDeviceControlError.describe("Failed have device enter recovery \(Self.errorMessage(for: status, calls: connectedDevice.calls))").build()
      }
    }
  }

  fileprivate func exitRecoveryAsync() async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    guard let recoveryDevice = device.recoveryModeDeviceRef else {
      throw FBDeviceControlError.describe("Device \(device) is not in recovery mode").build()
    }
    guard let setAutoBootFunc = device.calls.RecoveryModeDeviceSetAutoBoot else {
      throw FBDeviceControlError.describe("RecoveryModeDeviceSetAutoBoot function not available").build()
    }
    var status = setAutoBootFunc(recoveryDevice, 1)
    if status != 0 {
      throw FBDeviceControlError.describe("Failed to set autoboot for recovery device \(recoveryDevice) \(Self.errorMessage(for: status, calls: device.calls))").build()
    }
    guard let rebootFunc = device.calls.RecoveryDeviceReboot else {
      throw FBDeviceControlError.describe("RecoveryDeviceReboot function not available").build()
    }
    status = rebootFunc(recoveryDevice)
    if status != 0 {
      throw FBDeviceControlError.describe("Failed have device \(recoveryDevice) exit recovery \(Self.errorMessage(for: status, calls: device.calls))").build()
    }
  }

  // MARK: - Helpers

  private static func errorMessage(for status: Int32, calls: AMDCalls) -> String {
    if let copyErrorTextFunc = calls.CopyErrorText {
      return copyErrorTextFunc(status)?.takeRetainedValue() as String? ?? "Unknown error"
    }
    return "Unknown error"
  }
}
