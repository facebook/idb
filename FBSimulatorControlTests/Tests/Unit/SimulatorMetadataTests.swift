/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

@objc private final class MetadataDeviceType: NSObject {
  @objc let name = "Future Device"
  @objc let identifier = "future.device"
  @objc let productFamilyID: Int32 = 42
}

@objc private final class MetadataRuntime: NSObject {
  @objc let name = "Future Platform"
  @objc let identifier = "future.runtime"
  @objc let versionString = "99.10.2"
  @objc let buildVersionString = "99A100"
}

@objc private final class MetadataSimDevice: NSObject {
  @objc let deviceType = MetadataDeviceType()
  @objc let runtime = MetadataRuntime()
}

final class SimulatorMetadataTests: XCTestCase {
  func testMissingMetadataRemainsDescribable() {
    let configuration = FBSimulatorConfiguration.configuration(deviceType: nil, runtime: nil)
    XCTAssertEqual(configuration.device.model.rawValue, "unknown")
    XCTAssertEqual(configuration.os.versionString, "")
    XCTAssertNil(configuration.runtimeIdentifier)
  }

  func testDifferentVersionsWithoutIdentifiersRemainDistinct() {
    let device = DeviceType.generic(withName: "Future Device")
    let name = FBOSVersionName(rawValue: "Future Platform")
    let first = FBSimulatorConfiguration(device: device, os: OSVersion(name: name, versionString: "99.0"))
    let second = FBSimulatorConfiguration(device: device, os: OSVersion(name: name, versionString: "100.0"))
    XCTAssertEqual(Set([first, second]).count, 2)
  }

  func testRuntimeIdentifierPreservesIdentityAcrossDisplayNameChanges() {
    let device = DeviceType.generic(withName: "Future Device")
    let first = FBSimulatorConfiguration(device: device, os: .generic(withName: "FutureOS 99.0"), runtimeIdentifier: "future.runtime")
    let second = FBSimulatorConfiguration(device: device, os: .generic(withName: "RenamedOS 99.0"), runtimeIdentifier: "future.runtime")
    XCTAssertEqual(Set([first, second]).count, 1)
  }

  func testDifferentBuildsRemainDistinct() {
    let device = DeviceType.generic(withName: "Future Device")
    let os = OSVersion.generic(withName: "FutureOS 99.0")
    let first = FBSimulatorConfiguration(device: device, os: os, runtimeIdentifier: "future.runtime", runtimeBuildVersion: "99A1")
    let second = FBSimulatorConfiguration(device: device, os: os, runtimeIdentifier: "future.runtime", runtimeBuildVersion: "99A2")
    XCTAssertEqual(Set([first, second]).count, 2)
  }

  func testUncataloguedSimulatorUsesReportedMetadata() {
    let configuration = FBSimulatorConfiguration.inferSimulatorConfiguration(
      fromDevice: SimulatorTestSupport.asDevice(MetadataSimDevice()))
    XCTAssertEqual(configuration.device.model.rawValue, "Future Device")
    XCTAssertEqual(configuration.os.name.rawValue, "Future Platform")
    XCTAssertEqual(configuration.os.version.majorVersion, 99)
    XCTAssertEqual(configuration.os.version.minorVersion, 10)
    XCTAssertEqual(configuration.device.family, .familyUnknown)
    XCTAssertEqual(configuration.deviceTypeIdentifier, "future.device")
    XCTAssertEqual(configuration.runtimeIdentifier, "future.runtime")
    XCTAssertEqual(configuration.runtimeBuildVersion, "99A100")
  }
}
