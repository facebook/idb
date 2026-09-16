/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorKeychainCommands {

  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> SimulatorKeychainCommands {
    SimulatorKeychainCommands(simulator: simulator)
  }

  public func clear() async throws {
    try simulator.device.resetKeychain()
  }
}
