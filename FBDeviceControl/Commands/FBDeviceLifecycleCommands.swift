/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

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

  // MARK: - FBLifecycleCommands (legacy FBFuture entry points)

  @objc(resolveState:)
  public func resolveState(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await resolveStateAsync(state)
      return NSNull()
    }
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await resolveLeavesStateAsync(state)
      return NSNull()
    }
  }

  // MARK: - Async

  fileprivate func resolveStateAsync(_ state: FBiOSTargetState) async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    try await bridgeFBFutureVoid(FBiOSTargetResolveState(device, state))
  }

  fileprivate func resolveLeavesStateAsync(_ state: FBiOSTargetState) async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    try await bridgeFBFutureVoid(FBiOSTargetResolveLeavesState(device, state))
  }
}

// MARK: - AsyncLifecycleCommands

extension FBDeviceLifecycleCommands: AsyncLifecycleCommands {

  public func resolveState(_ state: FBiOSTargetState) async throws {
    try await resolveStateAsync(state)
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    try await resolveLeavesStateAsync(state)
  }
}
