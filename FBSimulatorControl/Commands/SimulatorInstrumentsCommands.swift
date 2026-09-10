/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorInstrumentsCommands: InstrumentsCommands {
  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> SimulatorInstrumentsCommands {
    SimulatorInstrumentsCommands(simulator: simulator)
  }

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  public func start(configuration: FBInstrumentsConfiguration, logger: any FBControlCoreLogger) async throws -> FBInstrumentsOperation {
    try await FBInstrumentsOperation.operation(target: simulator, configuration: configuration, logger: logger)
  }
}
