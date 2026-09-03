/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct FBSimulatorKeychainCommands {

  // MARK: - Properties

  private let simulator: FBSimulator

  // MARK: - Initializers

  public static func commands(with simulator: FBSimulator) -> FBSimulatorKeychainCommands {
    FBSimulatorKeychainCommands(simulator: simulator)
  }

  // MARK: - Private

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
