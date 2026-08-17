/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public final class FBSimulatorKeychainCommands: NSObject {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorKeychainCommands {
    FBSimulatorKeychainCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Private

  fileprivate func clearKeychain() async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    try simulator.device.resetKeychain()
  }
}

// MARK: - FBSimulator+KeychainCommands

extension FBSimulator: KeychainCommands {

  public func clearKeychain() async throws {
    try await keychainCommands().clearKeychain()
  }
}
