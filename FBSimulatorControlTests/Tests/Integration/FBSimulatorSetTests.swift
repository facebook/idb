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
