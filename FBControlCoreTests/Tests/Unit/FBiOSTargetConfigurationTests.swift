/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBiOSTargetConfigurationTests: XCTestCase {
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
