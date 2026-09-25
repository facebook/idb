/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class PeriodicStatsTimerTests: XCTestCase {

  func testFirstTickStartsTimer() {
    var timer = PeriodicStatsTimer(interval: .seconds(5))
    XCTAssertFalse(timer.hasStarted)
    XCTAssertNil(timer.firstTickTime)

    XCTAssertEqual(timer.tick(), .started)

    XCTAssertTrue(timer.hasStarted)
    XCTAssertNotNil(timer.firstTickTime)
  }

  func testTickPendingWithinInterval() {
    var timer = PeriodicStatsTimer(interval: .seconds(5))
    XCTAssertEqual(timer.tick(), .started)
    XCTAssertEqual(timer.tick(), .pending)
  }

  func testTickElapsedAfterInterval() {
    var timer = PeriodicStatsTimer(interval: .seconds(5))
    XCTAssertEqual(timer.tick(), .started)
    timer.backdateForTesting(by: .seconds(10))

    guard case .elapsed = timer.tick() else {
      XCTFail("Expected .elapsed after backdating past the interval")
      return
    }
  }
}
