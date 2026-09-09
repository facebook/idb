/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorKeychainCommands {

  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> SimulatorKeychainCommands {
    SimulatorKeychainCommands(simulator: simulator)
  }

  fileprivate func clearKeychain() async throws {
    try simulator.device.resetKeychain()
  }
}

// MARK: - FBSimulator+KeychainCommands

extension FBSimulator: KeychainCommands {

  public func clearKeychain() async throws {
    try await keychain.clearKeychain()
  }
}
