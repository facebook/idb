// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import XCTest

@testable import FBSimulatorControl

final class FBSimulatorConfigurationTests: XCTestCase {

  func testDefaultIsIphone() {
    let configuration = FBSimulatorConfiguration.default
    XCTAssertTrue(configuration.device.model.rawValue.contains("iPhone"))
    XCTAssertTrue(configuration.os.name.rawValue.contains("iOS"))
  }

  func testiPhoneConfiguration() {
    let configuration = FBSimulatorConfiguration.default.withDeviceModel(.modeliPhone7).withOSNamed(.nameiOS_10_0)
    XCTAssertEqual(configuration.device.model, .modeliPhone7)
    XCTAssertEqual(configuration.os.name, .nameiOS_10_0)
  }

  func testiPadConfiguration() {
    let configuration = FBSimulatorConfiguration.default.withDeviceModel(.modeliPadPro).withOSNamed(.nameiOS_10_0)
    XCTAssertEqual(configuration.device.model, .modeliPadPro)
    XCTAssertEqual(configuration.os.name, .nameiOS_10_0)
  }

  func testWatchOSConfiguration() {
    let watchModel = FBDeviceModel(rawValue: "Apple Watch Series 2 - 42mm")
    let watchOS = FBOSVersionName(rawValue: "watchOS 3.2")
    let configuration = FBSimulatorConfiguration.default.withDeviceModel(watchModel).withOSNamed(watchOS)
    XCTAssertEqual(configuration.device.model, watchModel)
    XCTAssertEqual(configuration.os.name, watchOS)
  }

  func testTVOSConfiguration() {
    let tvModel = FBDeviceModel(rawValue: "Apple TV")
    let tvOS = FBOSVersionName(rawValue: "tvOS 10.0")
    let configuration = FBSimulatorConfiguration.default.withDeviceModel(tvModel).withOSNamed(tvOS)
    XCTAssertEqual(configuration.device.model, tvModel)
    XCTAssertEqual(configuration.os.name, tvOS)
  }

  func testAdjustsOSOfIncompatableProductFamily() {
    let tvOS = FBOSVersionName(rawValue: "tvOS 10.0")
    let configuration = FBSimulatorConfiguration.default.withOSNamed(tvOS).withDeviceModel(.modeliPhone6)
    XCTAssertEqual(configuration.device.model, .modeliPhone6)
    XCTAssertTrue(configuration.os.name.rawValue.contains("iOS"))
  }

  func testUsesCurrentOSIfUnknownDeviceAppears() {
    let configuration = FBSimulatorConfiguration.default.withOSNamed(.nameiOS_10_0).withDeviceModel(FBDeviceModel(rawValue: "FooPad"))
    XCTAssertEqual(configuration.device.model, FBDeviceModel(rawValue: "FooPad"))
    XCTAssertEqual(configuration.os.name, .nameiOS_10_0)
  }

  func testUsesCurrentDeviceIfUnknownOSAppears() {
    let configuration = FBSimulatorConfiguration.default.withDeviceModel(.modeliPhone7).withOSNamed(FBOSVersionName(rawValue: "FooOS"))
    XCTAssertEqual(configuration.device.model, .modeliPhone7)
    XCTAssertEqual(configuration.os.name, FBOSVersionName(rawValue: "FooOS"))
  }
}
