/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Exercises launchctl service control end-to-end on a booted simulator. These run the
/// runtime's `launchctl` inside the simulator via the unified spawn+capture helper
/// (`FBSimulator.launchProcessConsumingOutput`), so a successful listing proves that path.
final class FBSimulatorLaunchCtlTests: FBSimulatorControlTestCase {

  func testListsServicesViaCoreSimulatorSpawn() async throws {
    guard
      let simulator = assertObtainsBootedSimulator(
        with: try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(FBDeviceModel(rawValue: "iPhone 8")),
        bootConfiguration: bootConfiguration
      )
    else {
      return
    }
    do {
      let services = try await simulator.listServices()
      XCTAssertFalse(services.isEmpty, "A booted simulator should report launchd services")
    } catch {
      XCTFail("launchctl list failed via CoreSimulator spawn: \(error)")
    }
    await assertShutdownSimulatorAndTerminateSession(simulator)
  }
}
