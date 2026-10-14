/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import FBVideoCore
import Foundation
import Testing

@Suite
struct PeriodicStatsTimerTests {

  @Test
  func firstTickStartsTimer() {
    var timer = PeriodicStatsTimer(interval: .seconds(5))
    #expect(!timer.hasStarted)
    #expect(timer.firstTickTime == nil)

    #expect(timer.tick() == .started)

    #expect(timer.hasStarted)
    #expect(timer.firstTickTime != nil)
  }

  @Test
  func tickPendingWithinInterval() {
    var timer = PeriodicStatsTimer(interval: .seconds(5))
    #expect(timer.tick() == .started)
    #expect(timer.tick() == .pending)
  }

  @Test
  func tickElapsedAfterInterval() {
    var timer = PeriodicStatsTimer(interval: .seconds(5))
    #expect(timer.tick() == .started)
    timer.backdateForTesting(by: .seconds(10))

    guard case .elapsed = timer.tick() else {
      Issue.record("Expected .elapsed after backdating past the interval")
      return
    }
  }
}
