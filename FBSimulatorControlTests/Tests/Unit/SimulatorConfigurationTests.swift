/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class SimulatorConfigurationTests: XCTestCase {

  /// Seeds from the static configuration tables instead of `defaultConfiguration()`, which
  /// resolves the newest runtime installed on the host. The seed OS is generic (empty product
  /// families), so `withDeviceModel` takes its early return and no test here consults the
  /// CoreSimulator service. Host-dependent assertions live in `SimulatorConfigurationBootTests`.
  private func hermeticBaseConfiguration() throws -> FBSimulatorConfiguration {
    let device = try XCTUnwrap(FBiOSTargetConfiguration.nameToDevice[.modeliPhone6])
    return FBSimulatorConfiguration(device: device, os: .generic(withName: "HermeticOS 0.0"))
  }

  func testiPhoneConfiguration() throws {
    let configuration = try hermeticBaseConfiguration().withDeviceModel(.modeliPhone7).withOSNamed(.nameiOS_10_0)
    XCTAssertEqual(configuration.device.model, .modeliPhone7)
    XCTAssertEqual(configuration.os.name, .nameiOS_10_0)
  }

  func testWatchOSConfiguration() throws {
    let watchModel = FBDeviceModel(rawValue: "Apple Watch Series 2 - 42mm")
    let watchOS = FBOSVersionName(rawValue: "watchOS 3.2")
    let configuration = try hermeticBaseConfiguration().withDeviceModel(watchModel).withOSNamed(watchOS)
    XCTAssertEqual(configuration.device.model, watchModel)
    XCTAssertEqual(configuration.os.name, watchOS)
  }

  func testTVOSConfiguration() throws {
    let tvModel = FBDeviceModel(rawValue: "Apple TV")
    let tvOS = FBOSVersionName(rawValue: "tvOS 10.0")
    let configuration = try hermeticBaseConfiguration().withDeviceModel(tvModel).withOSNamed(tvOS)
    XCTAssertEqual(configuration.device.model, tvModel)
    XCTAssertEqual(configuration.os.name, tvOS)
  }

  func testUsesCurrentOSIfUnknownDeviceAppears() throws {
    // Device first: applying a known OS first would send the unknown-device switch down the
    // service-backed compatible-runtime fallback instead of keeping the seed's families.
    let configuration = try hermeticBaseConfiguration().withDeviceModel(FBDeviceModel(rawValue: "FooPad")).withOSNamed(.nameiOS_10_0)
    XCTAssertEqual(configuration.device.model, FBDeviceModel(rawValue: "FooPad"))
    XCTAssertEqual(configuration.os.name, .nameiOS_10_0)
  }

  func testUsesCurrentDeviceIfUnknownOSAppears() throws {
    let configuration = try hermeticBaseConfiguration().withDeviceModel(.modeliPhone7).withOSNamed(FBOSVersionName(rawValue: "FooOS"))
    XCTAssertEqual(configuration.device.model, .modeliPhone7)
    XCTAssertEqual(configuration.os.name, FBOSVersionName(rawValue: "FooOS"))
  }
}
