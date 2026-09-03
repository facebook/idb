/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class FBSimulatorConfigurationTests: XCTestCase {

  override func setUpWithError() throws {
    try super.setUpWithError()
    // Every test here seeds from `defaultConfiguration()`, which resolves the newest runtime
    // *installed on this host* that supports its device family. A host with no simulator runtimes
    // cannot satisfy that, so these need one rather than being pure unit tests. Skip explicitly
    // instead of failing, so the suite distinguishes "not exercised here" from "broken".
    if (try? FBSimulatorConfiguration.defaultConfiguration()) == nil {
      throw XCTSkip("Requires at least one installed simulator runtime")
    }
  }

  func testDefaultIsIphone() throws {
    let configuration = try FBSimulatorConfiguration.defaultConfiguration()
    XCTAssertTrue(configuration.device.model.rawValue.contains("iPhone"))
    XCTAssertTrue(configuration.os.name.rawValue.contains("iOS"))
  }

  func testiPhoneConfiguration() throws {
    let configuration = try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(.modeliPhone7).withOSNamed(.nameiOS_10_0)
    XCTAssertEqual(configuration.device.model, .modeliPhone7)
    XCTAssertEqual(configuration.os.name, .nameiOS_10_0)
  }

  func testiPadConfiguration() throws {
    let configuration = try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(.modeliPadPro).withOSNamed(.nameiOS_10_0)
    XCTAssertEqual(configuration.device.model, .modeliPadPro)
    XCTAssertEqual(configuration.os.name, .nameiOS_10_0)
  }

  func testWatchOSConfiguration() throws {
    let watchModel = FBDeviceModel(rawValue: "Apple Watch Series 2 - 42mm")
    let watchOS = FBOSVersionName(rawValue: "watchOS 3.2")
    let configuration = try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(watchModel).withOSNamed(watchOS)
    XCTAssertEqual(configuration.device.model, watchModel)
    XCTAssertEqual(configuration.os.name, watchOS)
  }

  func testTVOSConfiguration() throws {
    let tvModel = FBDeviceModel(rawValue: "Apple TV")
    let tvOS = FBOSVersionName(rawValue: "tvOS 10.0")
    let configuration = try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(tvModel).withOSNamed(tvOS)
    XCTAssertEqual(configuration.device.model, tvModel)
    XCTAssertEqual(configuration.os.name, tvOS)
  }

  func testAdjustsOSOfIncompatableProductFamily() throws {
    let tvOS = FBOSVersionName(rawValue: "tvOS 10.0")
    let configuration = try FBSimulatorConfiguration.defaultConfiguration().withOSNamed(tvOS).withDeviceModel(.modeliPhone6)
    XCTAssertEqual(configuration.device.model, .modeliPhone6)
    XCTAssertTrue(configuration.os.name.rawValue.contains("iOS"))
  }

  func testUsesCurrentOSIfUnknownDeviceAppears() throws {
    let configuration = try FBSimulatorConfiguration.defaultConfiguration().withOSNamed(.nameiOS_10_0).withDeviceModel(FBDeviceModel(rawValue: "FooPad"))
    XCTAssertEqual(configuration.device.model, FBDeviceModel(rawValue: "FooPad"))
    XCTAssertEqual(configuration.os.name, .nameiOS_10_0)
  }

  func testUsesCurrentDeviceIfUnknownOSAppears() throws {
    let configuration = try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(.modeliPhone7).withOSNamed(FBOSVersionName(rawValue: "FooOS"))
    XCTAssertEqual(configuration.device.model, .modeliPhone7)
    XCTAssertEqual(configuration.os.name, FBOSVersionName(rawValue: "FooOS"))
  }
}
