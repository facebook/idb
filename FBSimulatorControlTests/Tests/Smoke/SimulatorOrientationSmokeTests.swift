/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class SimulatorOrientationSmokeTests: ProvidedSimulatorTestCase {
  func testPhysicalOrientationRoundTrips() async throws {
    let simulator = self.simulator!
    let original = try await simulator.orientation.current()
    guard (try? original.hidOrientation) != nil else {
      throw XCTSkip("Requires a restorable non-flat initial orientation")
    }
    addTeardownBlock { try await simulator.orientation.setOrientation(original) }
    let orientations: [SimulatorDeviceOrientation] = [.portrait, .landscapeLeft, .portraitUpsideDown, .landscapeRight]
    for expected in orientations {
      try await simulator.orientation.setOrientation(expected)
      var actual = try await simulator.orientation.current()
      for _ in 0..<20 where actual != expected {
        try await Task.sleep(nanoseconds: 100_000_000)
        actual = try await simulator.orientation.current()
      }
      XCTAssertEqual(actual, expected)
    }
  }
}
