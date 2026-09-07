/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Exercises the simulator lifecycle that this framework owns end-to-end: create, boot,
/// shutdown, delete. This is the one suite that must manage its own simulators — the lifecycle
/// is the unit under test.
final class FBSimulatorLaunchTests: FBSimulatorControlTestCase {

  func testBootShutdownLifecycle() async throws {
    let simulator = try await obtainBootedSimulator()
    XCTAssertEqual(simulator.state, .booted)
    try await shutdownAndDelete(simulator)
  }
}
