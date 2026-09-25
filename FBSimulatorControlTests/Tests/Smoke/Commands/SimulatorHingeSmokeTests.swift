/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class SimulatorHingeSmokeTests: ProvidedSimulatorTestCase {
  func testHingeAngleRoundTrips() async throws {
    let simulator = self.simulator!
    let original: SimulatorHingeAngle
    do {
      original = try await simulator.hinge.current()
    } catch SimulatorCoreDeviceError.unsupported(let reason) {
      // A runtime without a hinge has no angle to round trip.
      throw XCTSkip(reason)
    }
    addTeardownBlock { try await simulator.hinge.set(original) }
    for degrees in [0.0, 180.0, 90.0] {
      let expected = try SimulatorHingeAngle(degrees: degrees)
      try await simulator.hinge.set(expected)
      // The hinge animates to the requested angle; a read during the animation is between endpoints.
      var actual = try await simulator.hinge.current()
      for _ in 0..<50 where actual != expected {
        try await Task.sleep(nanoseconds: 100_000_000)
        actual = try await simulator.hinge.current()
      }
      XCTAssertEqual(actual, expected)
    }
  }
}
