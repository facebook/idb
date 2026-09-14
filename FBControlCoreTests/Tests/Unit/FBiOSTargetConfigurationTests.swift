/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBiOSTargetConfigurationTests: XCTestCase {
  func testMetadataDoesNotRequireKnownNames() {
    let device = DeviceType(model: FBDeviceModel(rawValue: "Future Device"), family: .familyUnknown)
    let os = OSVersion(name: FBOSVersionName(rawValue: "Future Platform"), versionString: "99.10.2")
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
    let os = OSVersion(name: FBOSVersionName(rawValue: "iOS 15.2 Beta"), versionString: "99.10.2")
    XCTAssertEqual(os.versionString, "99.10.2")
    XCTAssertEqual(os.version.majorVersion, 99)
  }

  func testMissingVersionDoesNotCrash() {
    let os = OSVersion.generic(withName: "unknown")
    XCTAssertEqual(os.versionString, "")
    XCTAssertEqual(os.version.majorVersion, 0)
  }

  static var deviceTypeConfigurations: [DeviceType] {
    return Array(FBiOSTargetConfiguration.nameToDevice.values)
  }

  static var osVersionConfigurations: [OSVersion] {
    return Array(FBiOSTargetConfiguration.nameToOSVersion.values)
  }

  func testDeviceTypeEqualityConsidersOnlyTheModel() {
    guard let catalogued = FBiOSTargetConfigurationTests.deviceTypeConfigurations.first(where: { !$0.productTypes.isEmpty }) else {
      return XCTFail("No catalogued device type carries product types")
    }
    let generic = DeviceType.generic(withName: catalogued.model.rawValue)

    XCTAssertNotEqual(catalogued.productTypes, generic.productTypes)
    XCTAssertNotEqual(catalogued.family, generic.family)

    // Equality and hashing are by model alone; every other field is catalogue data derived from it.
    XCTAssertEqual(catalogued, generic)
    XCTAssertEqual(catalogued.hashValue, generic.hashValue)
  }

  func testOSVersionEqualityConsidersOnlyTheName() {
    guard let catalogued = FBiOSTargetConfigurationTests.osVersionConfigurations.first(where: { !$0.families.isEmpty }) else {
      return XCTFail("No catalogued OS version carries families")
    }
    let generic = OSVersion.generic(withName: catalogued.name.rawValue)

    XCTAssertNotEqual(catalogued.families, generic.families)

    // Equality and hashing are by name alone; families is catalogue data derived from it.
    XCTAssertEqual(catalogued, generic)
    XCTAssertEqual(catalogued.hashValue, generic.hashValue)
  }

  func testScreenInfoHashTruncatesScale() {
    let integral = FBiOSTargetScreenInfo(widthPixels: 640, heightPixels: 960, scale: 2)
    let fractional = FBiOSTargetScreenInfo(widthPixels: 640, heightPixels: 960, scale: 2.5)

    // The hash casts the scale to Int, so a fractional difference collides while equality still separates them.
    XCTAssertNotEqual(integral, fractional)
    XCTAssertEqual(integral.hashValue, fractional.hashValue)
  }
}
