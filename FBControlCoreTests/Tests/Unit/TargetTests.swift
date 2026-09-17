/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import XCTest

final class TargetTests: XCTestCase {
  func testVersionComponentsDetermineOrdering() {
    let earlier = TargetDouble()
    let later = TargetDouble()
    earlier.osVersion = .generic(withName: "FutureOS 27.9")
    later.osVersion = .generic(withName: "FutureOS 27.10")
    XCTAssertEqual(earlier.compare(later), .orderedAscending)
    earlier.osVersion = .generic(withName: "FutureOS 27.10")
    later.osVersion = .generic(withName: "FutureOS 27.10.1")
    XCTAssertEqual(earlier.compare(later), .orderedAscending)
  }

  static var iPhoneDeviceTypes: [DeviceType] {
    ["Phone A", "Phone B"].map { DeviceType(model: FBDeviceModel(rawValue: $0), family: .familyiPhone) }
  }

  static var iPadDeviceTypes: [DeviceType] {
    ["Pad A", "Pad B"].map { DeviceType(model: FBDeviceModel(rawValue: $0), family: .familyiPad) }
  }

  func testDevicesOrderedFirst() {
    let first = TargetDouble()
    first.targetType = .device
    first.state = .booted
    first.deviceType = DeviceType(model: FBDeviceModel(rawValue: "Future Phone"), family: .familyiPhone)
    first.osVersion = OSVersion.generic(withName: "FutureOS 99.0")

    let second = TargetDouble()
    second.targetType = .simulator
    second.state = .booted
    second.deviceType = DeviceType(model: FBDeviceModel(rawValue: "Future Phone"), family: .familyiPhone)
    second.osVersion = OSVersion.generic(withName: "FutureOS 99.0")

    XCTAssertEqual(first.compare(second), .orderedDescending)
  }

  func testOSVersionOrdering() {
    let first = TargetDouble()
    first.targetType = .device
    first.state = .booted
    first.deviceType = DeviceType(model: FBDeviceModel(rawValue: "Future Phone"), family: .familyiPhone)
    first.osVersion = OSVersion.generic(withName: "FutureOS 99.0")

    let second = TargetDouble()
    second.targetType = .device
    second.deviceType = DeviceType(model: FBDeviceModel(rawValue: "Future Phone"), family: .familyiPhone)
    second.osVersion = OSVersion.generic(withName: "FutureOS 99.1")

    XCTAssertEqual(first.compare(second), .orderedAscending)
  }

  func testiPhoneComesBeforeiPad() {
    let deviceTypes = TargetTests.iPhoneDeviceTypes + TargetTests.iPadDeviceTypes
    var input: [any TargetInfo] = []
    for deviceType in deviceTypes {
      let target = TargetDouble()
      target.targetType = .device
      target.state = .booted
      target.deviceType = deviceType
      target.osVersion = OSVersion.generic(withName: "FutureOS 99.0")
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
