/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

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

  // Inlined from FBControlCoreValueTestCase since Swift can't see same-target ObjC headers
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
