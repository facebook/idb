// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import Foundation

@objc(FBDeviceLifecycleCommands)
public class FBDeviceLifecycleCommands: NSObject, FBLifecycleCommands {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBLifecycleCommands

  @objc(resolveState:)
  public func resolveState(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return FBiOSTargetResolveState(device, state)
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return FBiOSTargetResolveLeavesState(device, state)
  }
}
