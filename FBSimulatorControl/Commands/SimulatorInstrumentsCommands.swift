/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorInstrumentsCommands: InstrumentsCommands {
  private let simulator: Simulator

  public init(simulator: Simulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  public func start(configuration: InstrumentsConfiguration, logger: any ControlCoreLogger) async throws -> InstrumentsOperation {
    try await InstrumentsOperation.operation(target: simulator, configuration: configuration, logger: logger)
  }
}
