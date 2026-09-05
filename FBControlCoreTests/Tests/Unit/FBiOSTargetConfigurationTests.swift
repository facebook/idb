/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBiOSTargetConfigurationTests: XCTestCase {
  static var deviceTypeConfigurations: [FBDeviceType] {
    return Array(FBiOSTargetConfiguration.nameToDevice.values)
  }

  static var osVersionConfigurations: [FBOSVersion] {
    return Array(FBiOSTargetConfiguration.nameToOSVersion.values)
  }

  static var screenConfigurations: [FBiOSTargetScreenInfo] {
    return [
      FBiOSTargetScreenInfo(widthPixels: 320, heightPixels: 480, scale: 1),
      FBiOSTargetScreenInfo(widthPixels: 640, heightPixels: 960, scale: 2),
    ]
  }

  func testDeviceTypes() {
    let configurations = FBiOSTargetConfigurationTests.deviceTypeConfigurations
    assertEqualityOfCopy(configurations)
  }

  func testOSVersions() {
    let configurations = FBiOSTargetConfigurationTests.osVersionConfigurations
    assertEqualityOfCopy(configurations)
  }

  func testScreenSizes() {
    let configurations = FBiOSTargetConfigurationTests.screenConfigurations
    assertEqualityOfCopy(configurations)
  }

  func testDeviceTypeEqualityConsidersOnlyTheModel() {
    guard let catalogued = FBiOSTargetConfigurationTests.deviceTypeConfigurations.first(where: { !$0.productTypes.isEmpty }) else {
      return XCTFail("No catalogued device type carries product types")
    }
    let generic = FBDeviceType.generic(withName: catalogued.model.rawValue)

    XCTAssertNotEqual(catalogued.productTypes, generic.productTypes)
    XCTAssertNotEqual(catalogued.family, generic.family)

    // Equality and hashing are by model alone; every other field is catalogue data derived from it.
    XCTAssertEqual(catalogued, generic)
    XCTAssertEqual(catalogued.hash, generic.hash)
  }

  func testOSVersionEqualityConsidersOnlyTheName() {
    guard let catalogued = FBiOSTargetConfigurationTests.osVersionConfigurations.first(where: { !$0.families.isEmpty }) else {
      return XCTFail("No catalogued OS version carries families")
    }
    let generic = FBOSVersion.generic(withName: catalogued.name.rawValue)

    XCTAssertNotEqual(catalogued.families, generic.families)

    // Equality and hashing are by name alone; families is catalogue data derived from it.
    XCTAssertEqual(catalogued, generic)
    XCTAssertEqual(catalogued.hash, generic.hash)
  }

  func testScreenInfoHashTruncatesScale() {
    let integral = FBiOSTargetScreenInfo(widthPixels: 640, heightPixels: 960, scale: 2)
    let fractional = FBiOSTargetScreenInfo(widthPixels: 640, heightPixels: 960, scale: 2.5)

    // `hash` casts the scale to Int, so a fractional difference collides while `isEqual` still separates them.
    XCTAssertNotEqual(integral, fractional)
    XCTAssertEqual(integral.hash, fractional.hash)
  }

  // Swift tests cannot import this target's ObjC `FBControlCoreValueTestCase`, so the helper is duplicated here.
  private func assertEqualityOfCopy(_ values: [NSObject]) {
    for value in values {
      let valueCopy = value.copy() as! NSObject
      let valueCopyCopy = valueCopy.copy() as! NSObject
      XCTAssertEqual(value, valueCopy)
      XCTAssertEqual(value, valueCopyCopy)
      XCTAssertEqual(valueCopy, valueCopyCopy)
    }
  }
}
