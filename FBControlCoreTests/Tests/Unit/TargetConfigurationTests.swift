/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class TargetConfigurationTests: XCTestCase {
  func testMetadataDoesNotRequireKnownNames() {
    let device = DeviceType(model: DeviceModel(rawValue: "Future Device"), family: .familyUnknown)
    let os = OSVersion(name: OSVersionName(rawValue: "Future Platform"), versionString: "99.10.2")
    XCTAssertEqual(device.model.rawValue, "Future Device")
    XCTAssertEqual(os.name.rawValue, "Future Platform")
    XCTAssertEqual(os.version.majorVersion, 99)
    XCTAssertEqual(os.version.minorVersion, 10)
    XCTAssertEqual(os.version.patchVersion, 2)
  }

  func testVersionWithoutPlatformName() {
    let os = OSVersion.generic(withName: "27.10.2")
    XCTAssertEqual(os.versionString, "27.10.2")
    XCTAssertEqual(os.version.majorVersion, 27)
    XCTAssertEqual(os.version.minorVersion, 10)
    XCTAssertEqual(os.version.patchVersion, 2)
  }

  func testVersionWithTrailingQualifier() {
    let os = OSVersion.generic(withName: "iOS 15.2 Beta")
    XCTAssertEqual(os.versionString, "15.2")
    XCTAssertEqual(os.version.majorVersion, 15)
    XCTAssertEqual(os.version.minorVersion, 2)
  }

  func testExplicitVersionOverridesDisplayName() {
    let os = OSVersion(name: OSVersionName(rawValue: "iOS 15.2 Beta"), versionString: "99.10.2")
    XCTAssertEqual(os.versionString, "99.10.2")
    XCTAssertEqual(os.version.majorVersion, 99)
  }

  func testMissingVersionDoesNotCrash() {
    let os = OSVersion.generic(withName: "unknown")
    XCTAssertEqual(os.versionString, "")
    XCTAssertEqual(os.version.majorVersion, 0)
  }

  func testDeviceTypeEqualityConsidersOnlyTheModel() {
    let described = DeviceType(model: DeviceModel(rawValue: "Future Device"), family: .familyiPad)
    let generic = DeviceType.generic(withName: "Future Device")
    XCTAssertNotEqual(described.family, generic.family)
    XCTAssertEqual(described, generic)
    XCTAssertEqual(described.hashValue, generic.hashValue)
  }

  func testOSVersionEqualityConsidersOnlyTheName() {
    let described = OSVersion(name: OSVersionName(rawValue: "Future Platform"), versionString: "99.0")
    let generic = OSVersion.generic(withName: "Future Platform")
    XCTAssertNotEqual(described.versionString, generic.versionString)
    XCTAssertEqual(described, generic)
    XCTAssertEqual(described.hashValue, generic.hashValue)
  }

  func testScreenInfoHashTruncatesScale() {
    let integral = TargetScreenInfo(widthPixels: 640, heightPixels: 960, scale: 2)
    let fractional = TargetScreenInfo(widthPixels: 640, heightPixels: 960, scale: 2.5)

    // The hash casts the scale to Int, so a fractional difference collides while equality still separates them.
    XCTAssertNotEqual(integral, fractional)
    XCTAssertEqual(integral.hashValue, fractional.hashValue)
  }
}
