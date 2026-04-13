/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceRecoveryCommands)
public class FBDeviceRecoveryCommands: NSObject, FBDeviceRecoveryCommandsProtocol, FBiOSTargetCommand {
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

  // MARK: FBDeviceRecoveryCommands Implementation

  @objc
  public func enterRecovery() -> FBFuture<NSNull> {
    return self.device!
      .connectToDevice(withPurpose: "enter_recovery")
      .onQueue(
        self.device!.workQueue,
        pop: { (device: any FBDeviceCommands) -> FBFuture<AnyObject> in
          guard let enterRecoveryFunc = device.calls.EnterRecovery else {
            return FBDeviceControlError.describe("EnterRecovery function not available").failFuture()
          }
          let status = enterRecoveryFunc(device.amDeviceRef)
          if status != 0 {
            let internalMessage: String
            if let copyErrorTextFunc = device.calls.CopyErrorText {
              internalMessage = copyErrorTextFunc(status)?.takeRetainedValue() as String? ?? "Unknown error"
            } else {
              internalMessage = "Unknown error"
            }
            return FBDeviceControlError.describe("Failed have device enter recovery \(internalMessage)").failFuture()
          }
          return FBFuture(result: NSNull() as AnyObject)
        }) as! FBFuture<NSNull>
  }

  @objc
  public func exitRecovery() -> FBFuture<NSNull> {
    guard let device = self.device else {
      return FBDeviceControlError.describe("Device is nil").failFuture() as! FBFuture<NSNull>
    }
    return FBFuture.onQueue(
      device.workQueue,
      resolve: {
        guard let recoveryDevice = device.recoveryModeDeviceRef else {
          return FBDeviceControlError.describe("Device \(device) is not in recovery mode").failFuture()
        }
        guard let setAutoBootFunc = device.calls.RecoveryModeDeviceSetAutoBoot else {
          return FBDeviceControlError.describe("RecoveryModeDeviceSetAutoBoot function not available").failFuture()
        }
        var status = setAutoBootFunc(recoveryDevice, 1)
        if status != 0 {
          let internalMessage: String
          if let copyErrorTextFunc = device.calls.CopyErrorText {
            internalMessage = copyErrorTextFunc(status)?.takeRetainedValue() as String? ?? "Unknown error"
          } else {
            internalMessage = "Unknown error"
          }
          return FBDeviceControlError.describe("Failed to set autoboot for recovery device \(recoveryDevice) \(internalMessage)").failFuture()
        }
        guard let rebootFunc = device.calls.RecoveryDeviceReboot else {
          return FBDeviceControlError.describe("RecoveryDeviceReboot function not available").failFuture()
        }
        status = rebootFunc(recoveryDevice)
        if status != 0 {
          let internalMessage: String
          if let copyErrorTextFunc = device.calls.CopyErrorText {
            internalMessage = copyErrorTextFunc(status)?.takeRetainedValue() as String? ?? "Unknown error"
          } else {
            internalMessage = "Unknown error"
          }
          return FBDeviceControlError.describe("Failed have device \(recoveryDevice) exit recovery \(internalMessage)").failFuture()
        }
        return FBFuture(result: NSNull() as AnyObject)
      }) as! FBFuture<NSNull>
  }
}
