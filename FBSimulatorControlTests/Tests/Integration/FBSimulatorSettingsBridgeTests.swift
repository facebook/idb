/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Exercises the `SimulatorFrameworkBridge`-backed settings end-to-end on a booted
/// simulator. These spawn the bridge helper inside the simulator via CoreSimulator
/// (`FBSimulator.launchProcessConsumingOutput`) rather than `simctl spawn`; a successful
/// round-trip proves the helper runs under the CoreSimulator launchd domain.
final class FBSimulatorSettingsBridgeTests: FBSimulatorControlTestCase {

  func testRunsSimulatorFrameworkBridgeViaCoreSimulator() async throws {
    guard
      let simulator = assertObtainsBootedSimulator(
        with: try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(FBDeviceModel(rawValue: "iPhone 8")),
        bootConfiguration: bootConfiguration
      )
    else {
      return
    }
    do {
      _ = try await simulator.listProxy()
      _ = try await simulator.listDns()
    } catch {
      XCTFail("SimulatorFrameworkBridge command failed via CoreSimulator spawn: \(error)")
    }
    await assertShutdownSimulatorAndTerminateSession(simulator)
  }
}
