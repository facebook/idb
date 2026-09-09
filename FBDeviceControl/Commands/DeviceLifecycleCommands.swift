/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public final class DeviceLifecycleCommands {
  private weak var device: FBDevice?

  public class func commands(with device: FBDevice) -> DeviceLifecycleCommands {
    DeviceLifecycleCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Async

  fileprivate func resolveState(_ state: FBiOSTargetState) async throws {
    guard let device else {
      throw DeviceNilError.deviceNil
    }
    try await FBiOSTargetResolveState(device, state)
  }

  fileprivate func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    guard let device else {
      throw DeviceNilError.deviceNil
    }
    try await FBiOSTargetResolveLeavesState(device, state)
  }
}

// MARK: - FBDevice+LifecycleCommands

extension FBDevice: LifecycleCommands {

  public func resolveState(_ state: FBiOSTargetState) async throws {
    try await lifecycle.resolveState(state)
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    try await lifecycle.resolveLeavesState(state)
  }
}
