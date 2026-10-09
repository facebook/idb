/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBSimulatorControl

// The simulator's REPL capability, added onto `Simulator` from outside `FBSimulatorControl` so
// that consumers with no interest in injecting code do not link it.
extension Simulator {

  public var repl: SimulatorReplCommands {
    SimulatorReplCommands.commands(with: self)
  }
}
