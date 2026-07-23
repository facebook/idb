/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

final class FBSimulatorSetTests: FBSimulatorSetTestCase {

  func testInflatesSimulators() {
    createSet(withExistingSimDeviceSpecs: [
      ["name": "iPhone 5", "state": FBiOSTargetState.creating.rawValue],
      ["name": "iPhone 5", "state": FBiOSTargetState.shutdown.rawValue],
      ["name": "iPhone 5", "state": FBiOSTargetState.booted.rawValue],
      ["name": "iPhone 6s", "state": FBiOSTargetState.shuttingDown.rawValue],
      ["name": "iPad 2", "state": FBiOSTargetState.booted.rawValue],
      ["name": "iPad Air", "state": FBiOSTargetState.booted.rawValue],
      ["name": "iPad Air 2", "state": FBiOSTargetState.creating.rawValue],
      ["name": "iPhone 5", "state": FBiOSTargetState.shutdown.rawValue, "os": "iOS 10.0"],
    ])

    let simulators = self.set.allSimulators
    XCTAssertEqual(simulators.count, 8)

    var simulator = simulators[0]
    XCTAssertEqual(simulator.name, "iPhone 5")
    XCTAssertEqual(simulator.state, .creating)
    XCTAssert(simulator.set === self.set)

    simulator = simulators[1]
    XCTAssertEqual(simulator.name, "iPhone 5")
    XCTAssertEqual(simulator.state, .shutdown)
    XCTAssert(simulator.set === self.set)

    simulator = simulators[2]
    XCTAssertEqual(simulator.name, "iPhone 5")
    XCTAssertEqual(simulator.state, .booted)
    XCTAssert(simulator.set === self.set)

    simulator = simulators[3]
    XCTAssertEqual(simulator.name, "iPhone 6s")
    XCTAssertEqual(simulator.state, .shuttingDown)
    XCTAssert(simulator.set === self.set)

    simulator = simulators[4]
    XCTAssertEqual(simulator.name, "iPad 2")
    XCTAssertEqual(simulator.state, .booted)
    XCTAssert(simulator.set === self.set)

    simulator = simulators[5]
    XCTAssertEqual(simulator.name, "iPad Air")
    XCTAssertEqual(simulator.state, .booted)
    XCTAssert(simulator.set === self.set)

    simulator = simulators[6]
    XCTAssertEqual(simulator.name, "iPad Air 2")
    XCTAssertEqual(simulator.state, .creating)
    XCTAssert(simulator.set === self.set)

    simulator = simulators[7]
    XCTAssertEqual(simulator.name, "iPhone 5")
    XCTAssertEqual(simulator.state, .shutdown)
    XCTAssert(simulator.set === self.set)
  }

  func testInflatesBootedSimulatorWithUnavailableCryptexRuntimeMetadata() {
    let simulators = createSet(withExistingSimDeviceSpecs: [
      [
        "name": "iPhone 17 Pro",
        "state": FBiOSTargetState.booted.rawValue,
        "os": "iOS 27.0",
        "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
        "hasRuntimeMetadata": false,
        "available": false,
      ],
    ])

    XCTAssertEqual(simulators.count, 1)
    XCTAssertEqual(simulators[0].state, .booted)
    XCTAssertEqual(simulators[0].osVersion.name.rawValue, "iOS 27.0")
    XCTAssertEqual(simulators[0].deviceType.model.rawValue, "iPhone 17 Pro")
  }

  func testInflationPrefersRealRuntimeNameOverSynthesizedIdentifierName() {
    // The real CoreSimulator runtime name ("iOS 10.3.1") must win over the name
    // synthesized from the runtime identifier ("iOS 10.3"), otherwise exact-name
    // runtime matching fails against the installed runtime.
    let simulators = createSet(withExistingSimDeviceSpecs: [
      [
        "name": "iPhone 7",
        "state": FBiOSTargetState.booted.rawValue,
        "os": "iOS 10.3.1",
        "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-10-3",
        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-7",
      ],
    ])

    XCTAssertEqual(simulators.count, 1)
    XCTAssertEqual(simulators[0].osVersion.name.rawValue, "iOS 10.3.1")
  }

  func testInflationPrefersRealRuntimeNameForVisionOSIdentifierPrefix() {
    // visionOS runtime identifiers use the legacy "xrOS" prefix; the device's real
    // runtime name must win so we report "visionOS 2.0" instead of "xrOS 2.0".
    let simulators = createSet(withExistingSimDeviceSpecs: [
      [
        "name": "Apple Vision Pro",
        "state": FBiOSTargetState.booted.rawValue,
        "os": "visionOS 2.0",
        "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.xrOS-2-0",
        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro",
      ],
    ])

    XCTAssertEqual(simulators.count, 1)
    XCTAssertEqual(simulators[0].osVersion.name.rawValue, "visionOS 2.0")
  }

  func testReferencesForSimulatorsAreTheSame() {
    createSet(withExistingSimDeviceSpecs: [
      ["name": "iPhone 5", "state": FBiOSTargetState.creating.rawValue],
      ["name": "iPhone 5", "state": FBiOSTargetState.shutdown.rawValue],
      ["name": "iPhone 5", "state": FBiOSTargetState.booted.rawValue],
      ["name": "iPhone 6s", "state": FBiOSTargetState.shuttingDown.rawValue],
      ["name": "iPad 2", "state": FBiOSTargetState.booted.rawValue],
      ["name": "iPad Air", "state": FBiOSTargetState.booted.rawValue],
      ["name": "iPad Air 2", "state": FBiOSTargetState.creating.rawValue],
      ["name": "iPhone 5", "state": FBiOSTargetState.shutdown.rawValue, "os": "iOS 10.0"],
    ])

    let firstFetch = self.set.allSimulators
    let secondFetch = self.set.allSimulators
    XCTAssertEqual(firstFetch, secondFetch)

    // Reference equality.
    for index in 0..<firstFetch.count {
      XCTAssert(firstFetch[index] === secondFetch[index])
    }
  }
}
