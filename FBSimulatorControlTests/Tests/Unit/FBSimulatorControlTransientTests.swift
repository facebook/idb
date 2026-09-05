/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorControlTransientTests: XCTestCase {

  // MARK: FBSimulatorBootConfiguration

  func testDefaultConfigurationHasVerifyUsable() {
    let config = FBSimulatorBootConfiguration.default
    XCTAssertTrue(
      config.options.contains(.verifyUsable),
      "Default configuration should have VerifyUsable option"
    )
    XCTAssertFalse(
      config.options.contains(.tieToProcessLifecycle),
      "Default configuration should not have TieToProcessLifecycle option"
    )
  }

  func testDefaultConfigurationHasEmptyEnvironment() {
    let config = FBSimulatorBootConfiguration.default
    XCTAssertNotNil(config.environment)
    XCTAssertEqual(config.environment.count, 0)
  }

  func testBootConfigurationDescription() {
    let config = FBSimulatorBootConfiguration(
      options: .tieToProcessLifecycle,
      environment: ["KEY": "VAL"]
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("Boot Environment"), "Description should contain 'Boot Environment'")
    XCTAssertTrue(desc.contains("Options"), "Description should contain 'Options'")
  }

  func testBootConfigurationDescriptionContainsDirectLaunch() {
    let config = FBSimulatorBootConfiguration(
      options: .tieToProcessLifecycle,
      environment: [:]
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("Direct Launch"), "Description should contain 'Direct Launch' for tieToProcessLifecycle")
  }

  func testBootConfigurationDescriptionWithoutDirectLaunch() {
    let config = FBSimulatorBootConfiguration(
      options: .verifyUsable,
      environment: [:]
    )
    let desc = config.description
    XCTAssertFalse(desc.contains("Direct Launch"), "Description should not contain 'Direct Launch' for verifyUsable only")
  }

  // MARK: FBSimulatorHIDEvent - Swipe

  func testSwipeDiagonalProducesCorrectStepCount() {
    // Diagonal: distance = sqrt(30^2 + 40^2) = 50, delta=10 -> 5 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 30, yEnd: 40, delta: 10, duration: 1.0)
    let expectedSteps = 5
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(swipe.subEvents?.count, expectedEvents)
  }

  func testSwipeShorterThanDeltaClampsToOneStep() {
    // distance = 5 < delta 10 gives Int(0.5) = 0 steps, which divides by zero in
    // dx/dy and yields NaN touch coordinates. Steps must be clamped to at least 1,
    // mirroring `pinchAt` and `pan`.
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 5, yEnd: 0, delta: 10, duration: 1.0)
    let expectedSteps = 1
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(swipe.subEvents?.count, expectedEvents)
    for event in swipe.subEvents ?? [] {
      if case let .touch(_, x, y, _) = event {
        XCTAssertTrue(x.isFinite && y.isFinite, "Swipe produced a non-finite coordinate (\(x), \(y))")
      }
    }
  }
}
