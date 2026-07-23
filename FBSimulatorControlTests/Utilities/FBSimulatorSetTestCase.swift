/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

/// A Test Case Template that creates a Set for mocking.
class FBSimulatorSetTestCase: XCTestCase {

  private(set) var set: FBSimulatorSet!

  @discardableResult
  func createSet(withExistingSimDeviceSpecs simulatorSpecs: [[String: Any]]) -> [FBSimulator] {
    var simDevices: [AnyObject] = []
    var availableSimDevices: [AnyObject] = []
    for simulatorSpec in simulatorSpecs {
      let name = simulatorSpec["name"] as! String
      let uuid = simulatorSpec["uuid"] as? NSUUID ?? NSUUID()
      let os = simulatorSpec["os"] as? String ?? "iOS 9.0"
      let version = os.components(separatedBy: CharacterSet.whitespaces).last ?? os
      let hasRuntimeMetadata = simulatorSpec["hasRuntimeMetadata"] as? Bool ?? true
      let isAvailable = simulatorSpec["available"] as? Bool ?? true
      let state: FBiOSTargetState
      if let stateRaw = simulatorSpec["state"] as? UInt {
        state = FBiOSTargetState(rawValue: stateRaw)!
      } else {
        state = .shutdown
      }

      let deviceType = FBSimulatorControlTests_SimDeviceType_Double()
      deviceType.name = name

      let runtime = FBSimulatorControlTests_SimDeviceRuntime_Double()
      runtime.name = os
      runtime.versionString = version

      let device = FBSimulatorControlTests_SimDevice_Double()
      device.name = name
      device.UDID = uuid
      device.state = UInt64(state.rawValue)
      device.deviceType = deviceType
      device.deviceTypeIdentifier = simulatorSpec["deviceTypeIdentifier"] as? String
        ?? "com.apple.CoreSimulator.SimDeviceType.\(name.replacingOccurrences(of: " ", with: "-"))"
      device.runtimeIdentifier = simulatorSpec["runtimeIdentifier"] as? String
        ?? "com.apple.CoreSimulator.SimRuntime.\(os.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ".", with: "-"))"
      device.runtime = hasRuntimeMetadata ? runtime : nil

      simDevices.append(device)
      if isAvailable {
        availableSimDevices.append(device)
      }
    }

    let deviceSet = FBSimulatorControlTests_SimDeviceSet_Double()
    deviceSet.availableDevices = availableSimDevices
    deviceSet.devices = simDevices

    let noLogger: (any FBControlCoreLogger)? = nil
    let noReporter: (any FBEventReporter)? = nil
    let configuration = FBSimulatorControlConfiguration(deviceSetPath: nil, logger: noLogger, reporter: noReporter)
    set = CreateSimulatorSetWithFakeDeviceSet(configuration, deviceSet)

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
