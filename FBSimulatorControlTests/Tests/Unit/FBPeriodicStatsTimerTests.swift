/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBPeriodicStatsTimerTests: XCTestCase {

  func testFirstTickStartsTimer() {
    var timer = FBPeriodicStatsTimer(interval: 5.0)
    XCTAssertFalse(timer.hasStarted)
    XCTAssertEqual(timer.firstTickTime, 0)

    XCTAssertEqual(timer.tick(), .started)

    XCTAssertTrue(timer.hasStarted)
    XCTAssertGreaterThan(timer.firstTickTime, 0)
  }

  func testTickPendingWithinInterval() {
    var timer = FBPeriodicStatsTimer(interval: 5.0)
    XCTAssertEqual(timer.tick(), .started)
    XCTAssertEqual(timer.tick(), .pending)
  }

  func testTickElapsedAfterInterval() {
    var timer = FBPeriodicStatsTimer(interval: 5.0)
    XCTAssertEqual(timer.tick(), .started)
    timer.backdateForTesting(by: 10.0)

    guard case .elapsed = timer.tick() else {
      XCTFail("Expected .elapsed after backdating past the interval")
      return
    }
  }
}
