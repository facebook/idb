/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class FBSimulatorLaunchTests: FBSimulatorControlTestCase {

  func testLaunchesSingleSimulator(_ configuration: FBSimulatorConfiguration) async {
    guard
      let simulator = await assertObtainsBootedSimulator(
        with: configuration,
        bootConfiguration: bootConfiguration
      )
    else {
      return
    }

    assertSimulatorBooted(simulator)
    await assertShutdownSimulatorAndTerminateSession(simulator)
  }

  func testLaunchesiPhone() async throws {
    await testLaunchesSingleSimulator(
      try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(FBDeviceModel(rawValue: "iPhone 8"))
    )
  }

  func testLaunchesiPad() async throws {
    await testLaunchesSingleSimulator(
      try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(FBDeviceModel(rawValue: "iPad Air 2"))
    )
  }

  func testLaunchesWatch() async throws {
    await testLaunchesSingleSimulator(
      try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(FBDeviceModel(rawValue: "Apple Watch - 42mm"))
    )
  }

  func testLaunchesTV() async throws {
    await testLaunchesSingleSimulator(
      try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(FBDeviceModel(rawValue: "Apple TV"))
    )
  }
}
