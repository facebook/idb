/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorPowerCommands: PowerCommands {
  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> SimulatorPowerCommands {
    SimulatorPowerCommands(simulator: simulator)
  }

  init(simulator: Simulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  public func shutdown() async throws {
    try await SimulatorShutdownStrategy.shutdown(simulator)
  }

  public func reboot() async throws {
    try await shutdown()
    try await simulator.lifecycle.boot(SimulatorBootConfiguration.default)
  }
}
