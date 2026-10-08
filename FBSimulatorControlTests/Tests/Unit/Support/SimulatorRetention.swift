/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation

/// Whether resolving a command keeps its simulator alive.
///
/// A simulator owns its `commandCache`; the cache owns whatever is resolved into it. A memoized
/// command that holds its simulator strongly therefore closes a cycle — simulator to cache to
/// command to simulator — and the simulator can never be released, which is why the memoized
/// commands hold `weak var simulator`. Commands built per call are free to hold it strongly:
/// nothing outlives the call that builds them.
///
/// Each library asserts this over every accessor it adds to `Simulator`, rather than over the
/// memoized ones, so the rule stays intact when a per-call command is later moved into the cache.
func simulatorSurvives(_ resolve: (Simulator) -> Void) -> Bool {
  weak var weakSimulator: Simulator?
  autoreleasepool {
    let simulator = SimulatorTestSupport.testableSimulator()
    weakSimulator = simulator
    resolve(simulator)
  }
  return weakSimulator != nil
}
