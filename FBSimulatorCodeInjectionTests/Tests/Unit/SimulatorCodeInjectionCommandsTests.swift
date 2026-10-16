/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorCodeInjection
@testable import FBSimulatorControl
import XCTest

/// The environment that arms an ordinary app launch, from the bundled shim or one the caller
/// supplies.
final class SimulatorCodeInjectionCommandsTests: XCTestCase {

  func testArmsALaunchWithTheBundledShimByDefault() throws {
    let simulator = SimulatorTestSupport.testableSimulator()

    let environment = try simulator.codeInjection.launchEnvironment(forApplication: "com.example.App")

    let shim = try XCTUnwrap(BundledResources.path(forItem: "libShimulator-iOS.dylib"))
    XCTAssertEqual(environment["DYLD_INSERT_LIBRARIES"], shim)
    XCTAssertEqual(environment["IDB_REPL_APP_AUTOSTART"], "1")
    XCTAssertEqual(environment["IDB_REPL_SOCKET_PATH"], replSocketPath(udid: simulator.udid, bundleID: "com.example.App"))
  }

  func testArmsALaunchWithASuppliedShimThenAdditionalLibraries() throws {
    let simulator = SimulatorTestSupport.testableSimulator()

    let environment = try simulator.codeInjection.launchEnvironment(
      forApplication: "com.example.App",
      shim: .path("/opt/shims/libShimulator-iOS.dylib"),
      additionalLibraries: ["/opt/shims/libExtra.dylib"])

    XCTAssertEqual(environment["DYLD_INSERT_LIBRARIES"], "/opt/shims/libShimulator-iOS.dylib:/opt/shims/libExtra.dylib")
  }
}
