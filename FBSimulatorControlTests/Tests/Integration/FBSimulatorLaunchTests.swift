/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

final class FBSimulatorLaunchTests: FBSimulatorControlTestCase {

  func testLaunchesSingleSimulator(_ configuration: FBSimulatorConfiguration) {
    guard
      let simulator = assertObtainsBootedSimulator(
        with: configuration,
        bootConfiguration: bootConfiguration
      )
    else {
      return
    }

    assertSimulatorBooted(simulator)
    assertShutdownSimulatorAndTerminateSession(simulator)
  }

  func testLaunchesiPhone() {
    testLaunchesSingleSimulator(
      FBSimulatorConfiguration.default.withDeviceModel(FBDeviceModel(rawValue: "iPhone 8"))
    )
  }

  func testLaunchesiPad() {
    testLaunchesSingleSimulator(
      FBSimulatorConfiguration.default.withDeviceModel(FBDeviceModel(rawValue: "iPad Air 2"))
    )
  }

  func testLaunchesWatch() {
    testLaunchesSingleSimulator(
      FBSimulatorConfiguration.default.withDeviceModel(FBDeviceModel(rawValue: "Apple Watch - 42mm"))
    )
  }

  func testLaunchesTV() {
    testLaunchesSingleSimulator(
      FBSimulatorConfiguration.default.withDeviceModel(FBDeviceModel(rawValue: "Apple TV"))
    )
  }

  // Commented out: causes target-level timeout (too slow with other tests)
  // func testCanUninstallApplication() {
  //   let application = tableSearchApplication
  //   let launch = tableSearchAppLaunch
  //   guard let simulator = assertObtainsBootedSimulator(withInstalledApplication: application) else { return }
  //
  //   var error: NSError?
  //   var success = simulator.launchApplication(launch).await(&error) != nil
  //   XCTAssertNil(error)
  //   XCTAssertTrue(success)
  //
  //   assertSimulator(simulator, isRunningApplicationFromConfiguration: launch)
  //
  //   success = simulator.uninstallApplication(withBundleID: application.identifier).await(&error) != nil
  //   XCTAssertNil(error)
  //   XCTAssertTrue(success)
  // }
}
