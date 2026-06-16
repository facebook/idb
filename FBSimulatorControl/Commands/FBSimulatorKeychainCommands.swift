/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// swiftlint:disable force_cast

@objc(FBSimulatorKeychainCommands)
public final class FBSimulatorKeychainCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorKeychainCommands {
    FBSimulatorKeychainCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Private

  fileprivate func clearKeychain() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try simulator.device.resetKeychain()
  }
}

// MARK: - FBSimulator+AsyncKeychainCommands

extension FBSimulator: AsyncKeychainCommands {

  public func clearKeychain() async throws {
    try await keychainCommands().clearKeychain()
  }
}
