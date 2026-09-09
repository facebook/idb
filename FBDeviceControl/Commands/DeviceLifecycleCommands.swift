/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct DeviceLifecycleCommands {
  private let device: FBDevice

  public static func commands(with device: FBDevice) -> DeviceLifecycleCommands {
    DeviceLifecycleCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Async

  fileprivate func resolveState(_ state: FBiOSTargetState) async throws {
    try await FBiOSTargetResolveState(device, state)
  }

  fileprivate func resolveLeavesState(_ state: FBiOSTargetState) async throws {
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
