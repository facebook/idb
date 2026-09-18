/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// A Test Case Template that creates a Set for mocking.
class SimulatorSetTestCase: XCTestCase {

  private(set) var set: SimulatorSet!

  @discardableResult
  func createSet(withExistingSimDeviceSpecs simulatorSpecs: [[String: Any]]) -> [Simulator] {
    var simDevices: [AnyObject] = []
    for simulatorSpec in simulatorSpecs {
      let name = simulatorSpec["name"] as! String
      let uuid = simulatorSpec["uuid"] as? NSUUID ?? NSUUID()
      let os = simulatorSpec["os"] as? String ?? "iOS 9.0"
      let version = os.components(separatedBy: CharacterSet.whitespaces).last ?? os
      let state: TargetState
      if let stateRaw = simulatorSpec["state"] as? UInt {
        state = TargetState(rawValue: stateRaw)!
      } else {
        state = .shutdown
      }

      let deviceType = SimDeviceTypeDouble()
      deviceType.name = name
      deviceType.productFamilyID = Int32(simulatorSpec["family"] as? Int ?? 1)

      let runtime = SimDeviceRuntimeDouble()
      runtime.name = os
      runtime.versionString = version

      let device = SimDeviceDouble()
      device.name = name
      device.UDID = uuid
      device.state = UInt64(state.rawValue)
      device.deviceType = deviceType
      device.runtime = runtime

      simDevices.append(device)
    }

    let deviceSet = SimDeviceSetDouble()
    deviceSet.availableDevices = simDevices

    let noLogger: (any ControlCoreLogger)? = nil
    let configuration = SimulatorControlConfiguration(deviceSetPath: nil, logger: noLogger)
    set = createSimulatorSet(configuration: configuration, fakeDeviceSet: deviceSet)

    let simulators = set.allSimulators
    XCTAssertEqual(simulators.count, simDevices.count)

    for index in 0..<simulators.count {
      let expected = simulatorSpecs[index]["name"] as! String
      let actual = simulators[index].deviceType.model
      XCTAssertEqual(expected as String, actual.rawValue as String)
    }

    return simulators
  }
}
