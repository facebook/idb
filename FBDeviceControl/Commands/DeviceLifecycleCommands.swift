/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct DeviceLifecycleCommands: LifecycleCommands {
  private let device: Device

  public static func commands(with device: Device) -> DeviceLifecycleCommands {
    DeviceLifecycleCommands(device: device)
  }

  init(device: Device) {
    self.device = device
  }

  // MARK: - Async

  public func resolveState(_ state: FBTargetState) async throws {
    try await TargetResolveState(device, state)
  }

  public func resolveLeavesState(_ state: FBTargetState) async throws {
    try await TargetResolveLeavesState(device, state)
  }
}
