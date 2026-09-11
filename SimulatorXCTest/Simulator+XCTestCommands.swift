/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@preconcurrency import FBSimulatorControl
import Foundation
import XCTestBootstrap

// The simulator's test capability, added onto `FBSimulator` from outside `FBSimulatorControl` so
// that consumers with no interest in running tests do not link XCTestBootstrap. `repl` is here for
// the same reason and not because the REPL is about testing: it hosts its control socket by running
// the shim's single test under the logic-test runner.
extension FBSimulator: @retroactive LogicTestTarget {

  public var xctest: SimulatorXCTestCommands {
    commandCache.resolve { SimulatorXCTestCommands.commands(with: self) }
  }

  public var repl: SimulatorReplCommands {
    SimulatorReplCommands.commands(with: self)
  }
}
