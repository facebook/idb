/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing

/// Pins `FBSimulatorSet`'s UDID lookup behavior.
@Suite("FBSimulatorSet UDID lookup")
struct FBSimulatorSetLookupTests {

  private static func makeSet(udids: [NSUUID]) -> FBSimulatorSet {
    let deviceSet = FBSimulatorControlTests_SimDeviceSet_Double()
    deviceSet.availableDevices = udids.map { udid in
      let deviceType = FBSimulatorControlTests_SimDeviceType_Double()
      deviceType.name = "iPhone 8"
      let runtime = FBSimulatorControlTests_SimDeviceRuntime_Double()
      runtime.name = "iOS 15.0"
      runtime.versionString = "15.0"
      let device = FBSimulatorControlTests_SimDevice_Double()
      device.name = "iPhone 8"
      device.UDID = udid
      device.deviceType = deviceType
      device.runtime = runtime
      return device
    }
    let configuration = FBSimulatorControlConfiguration(deviceSetPath: nil, logger: nil)
    return createSimulatorSet(configuration: configuration, fakeDeviceSet: deviceSet)
  }

  @Test func lookupByKnownUDIDReturnsTheSimulator() {
    let target = NSUUID()
    let set = Self.makeSet(udids: [NSUUID(), target, NSUUID()])
    #expect(set.simulator(withUDID: target.uuidString)?.udid == target.uuidString)
  }

  @Test func lookupByUnknownUDIDReturnsNil() {
    let set = Self.makeSet(udids: [NSUUID()])
    #expect(set.simulator(withUDID: NSUUID().uuidString) == nil)
  }
}
