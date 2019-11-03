/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
@testable import FBSimulatorControlKit
import XCTest

class EnvironmentTests: XCTestCase {
  let testEnvironment = [
    "FBSIMCTL_CHILD_FOO": "BAR",
    "PATH": "IGNORE",
    "FBSIMCTL_CHILD_BING": "BONG",
  ]

  func testAppendsEnvironmentToLaunchConfiguration() {
    let launchConfig = FBApplicationLaunchConfiguration(application: Fixtures.application, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())
    let actual = Action.launchApp(launchConfig).appendEnvironment(testEnvironment)
    let expected = Action.launchApp(launchConfig.withEnvironmentAdditions([
      "FOO": "BAR",
      "BING": "BONG",
    ]))
    XCTAssertEqual(expected, actual)
  }

  func testAppendsEnvironmentToXCTestLaunchConfiguration() {
    let launchConfig = FBApplicationLaunchConfiguration(application: Fixtures.application, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())

    let actual = Action.launchXCTest(FBTestLaunchConfiguration().withApplicationLaunchConfiguration(launchConfig)).appendEnvironment(testEnvironment)
    let expected = Action.launchXCTest(FBTestLaunchConfiguration().withApplicationLaunchConfiguration(launchConfig.withEnvironmentAdditions([
      "FOO": "BAR",
      "BING": "BONG",
    ])))

    XCTAssertEqual(expected, actual)
  }

  func testAppendsEnvironmentToBootConfiguration() {
    let bootConfig = FBSimulatorBootConfiguration.default.withBootEnvironment([
      "FOO": "BAR",
      "BING": "BONG",
    ])

    let actual = Action.boot(FBSimulatorBootConfiguration.default).appendEnvironment(testEnvironment)
    let expected = Action.boot(bootConfig)

    XCTAssertEqual(expected, actual)
  }
}
