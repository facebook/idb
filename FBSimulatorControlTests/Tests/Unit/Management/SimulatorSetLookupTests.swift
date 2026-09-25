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

@Suite("SimulatorSet UDID lookup")
struct SimulatorSetLookupTests {

  private static func makeSet(udids: [NSUUID]) -> SimulatorSet {
    let deviceSet = SimDeviceSetDouble()
    deviceSet.availableDevices = udids.map { udid in
      let deviceType = SimDeviceTypeDouble()
      deviceType.name = "iPhone 8"
      let runtime = SimDeviceRuntimeDouble()
      runtime.name = "iOS 15.0"
      runtime.versionString = "15.0"
      let device = SimDeviceDouble()
      device.name = "iPhone 8"
      device.UDID = udid
      device.deviceType = deviceType
      device.runtime = runtime
      return device
    }
    let configuration = SimulatorControlConfiguration(deviceSetPath: nil, logger: nil)
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
