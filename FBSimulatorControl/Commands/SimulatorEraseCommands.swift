/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorEraseCommands: EraseCommands {
  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> SimulatorEraseCommands {
    SimulatorEraseCommands(simulator: simulator)
  }

  init(simulator: Simulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  public func erase() async throws {
    try await SimulatorEraseStrategy.erase(simulator)
  }
}
