/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

import Foundation
import XCTest

@testable import FBControlCore

final class FBiOSTargetTests: XCTestCase {
  static var iPhoneModels: [FBDeviceModel] {
    return [
      .modeliPhone4s,
      .modeliPhone5,
      .modeliPhone5c,
      .modeliPhone5s,
      .modeliPhone6,
      .modeliPhone6Plus,
      .modeliPhone6S,
      .modeliPhone6SPlus,
      .modeliPhone7,
      .modeliPhone7Plus,
      .modeliPhoneSE_1stGeneration,
    ]
  }

  static var iPadModels: [FBDeviceModel] {
    return [
      .modeliPad2,
      .modeliPadAir,
      .modeliPadAir2,
      .modeliPadPro,
      .modeliPadPro_12_9_Inch,
      .modeliPadPro_9_7_Inch,
      .modeliPadRetina,
    ]
  }

  static func deviceTypes(forModels models: [FBDeviceModel]) -> [FBDeviceType] {
    var deviceTypes: [FBDeviceType] = []
    for model in models {
      deviceTypes.append(FBiOSTargetConfiguration.nameToDevice[model]!)
    }
    return deviceTypes
  }

  static var iPhoneDeviceTypes: [FBDeviceType] {
    return deviceTypes(forModels: iPhoneModels)
  }

  static var iPadDeviceTypes: [FBDeviceType] {
    return deviceTypes(forModels: iPadModels)
  }

  func testDevicesOrderedFirst() {
    let first = FBiOSTargetDouble()
    first.targetType = .device
    first.state = .booted
    first.deviceType = FBiOSTargetConfiguration.nameToDevice[.modeliPhone6S]
    first.osVersion = FBiOSTargetConfiguration.nameToOSVersion[.nameiOS_10_0]

    let second = FBiOSTargetDouble()
    second.targetType = .simulator
    second.state = .booted
    second.deviceType = FBiOSTargetConfiguration.nameToDevice[.modeliPhone6S]
    second.osVersion = FBiOSTargetConfiguration.nameToOSVersion[.nameiOS_10_0]

    XCTAssertEqual(FBiOSTargetComparison(first, second), .orderedDescending)
  }

  func testOSVersionOrdering() {
    let first = FBiOSTargetDouble()
    first.targetType = .device
    first.state = .booted
    first.deviceType = FBiOSTargetConfiguration.nameToDevice[.modeliPhone6S]
    first.osVersion = FBiOSTargetConfiguration.nameToOSVersion[.nameiOS_10_0]

    let second = FBiOSTargetDouble()
    second.targetType = .device
    second.deviceType = FBiOSTargetConfiguration.nameToDevice[.modeliPhone6S]
    second.osVersion = FBiOSTargetConfiguration.nameToOSVersion[.nameiOS_10_1]

    XCTAssertEqual(FBiOSTargetComparison(first, second), .orderedAscending)
  }

  func testStateOrdering() {
    let stateOrder: [FBiOSTargetState] = [
      .creating,
      .shutdown,
      .booting,
      .booted,
      .shuttingDown,
      .unknown,
    ]
    var input: [FBiOSTarget] = []
    for state in stateOrder {
      let target = FBiOSTargetDouble()
      target.targetType = .device
      target.state = state
      target.deviceType = FBiOSTargetConfiguration.nameToDevice[.modeliPhone6S]
      target.osVersion = FBiOSTargetConfiguration.nameToOSVersion[.nameiOS_10_0]
      input.append(target)
    }
    for (index, target) in input.enumerated() {
      let expected = stateOrder[index]
      let actual = target.state
      XCTAssertEqual(expected, actual)
    }
  }

  func testiPadComesBeforeiPhone() {
    let deviceTypes = FBiOSTargetTests.iPhoneDeviceTypes + FBiOSTargetTests.iPadDeviceTypes
    var input: [FBiOSTarget] = []
    for deviceType in deviceTypes {
      let target = FBiOSTargetDouble()
      target.targetType = .device
      target.state = .booted
      target.deviceType = deviceType
      target.osVersion = FBiOSTargetConfiguration.nameToOSVersion[.nameiOS_10_0]
      input.append(target)
    }
    let output = input.sorted { $0.compare($1) == .orderedAscending }
    XCTAssertEqual(input.count, output.count)
    for index in 0..<input.count {
      let expected = input[index].deviceType
      let actual = output[index].deviceType
      XCTAssertEqual(expected, actual)
    }
  }
}
