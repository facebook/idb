/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorPowerCommands: PowerCommands {
  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> SimulatorPowerCommands {
    SimulatorPowerCommands(simulator: simulator)
  }

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  public func shutdown() async throws {
    try await SimulatorShutdownStrategy.shutdown(simulator)
  }

  public func reboot() async throws {
    try await shutdown()
    try await simulator.lifecycle.boot(FBSimulatorBootConfiguration.default)
  }
}
