/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Host-dependent configuration assertions: they resolve against the runtimes installed on the
/// host, so they run in the Boot suite (whose workers guarantee runtimes) rather than Unit.
/// A plain `XCTestCase` — nothing here boots a simulator.
final class SimulatorConfigurationBootTests: XCTestCase {

  func testDefaultIsIphone() throws {
    let configuration = try FBSimulatorConfiguration.defaultConfiguration()
    XCTAssertTrue(configuration.device.model.rawValue.contains("iPhone"))
    XCTAssertTrue(configuration.os.name.rawValue.contains("iOS"))
  }

  func testAdjustsOSOfIncompatableProductFamily() throws {
    let tvOS = FBOSVersionName(rawValue: "tvOS 10.0")
    let configuration = try FBSimulatorConfiguration.defaultConfiguration().withOSNamed(tvOS).withDeviceModel(.modeliPhone6)
    XCTAssertEqual(configuration.device.model, .modeliPhone6)
    XCTAssertTrue(configuration.os.name.rawValue.contains("iOS"))
  }
}
