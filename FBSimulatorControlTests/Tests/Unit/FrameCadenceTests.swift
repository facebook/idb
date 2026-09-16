/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

/// How the eager cadence clock behaves when a push overshoots its frame budget.
final class FrameCadenceTests: XCTestCase {

  func testFirstTickFiresImmediately() async throws {
    var iterator = FrameCadence(framesPerSecond: 10, logger: CapturingLogger()).makeAsyncIterator()
    let started = ContinuousClock.now
    let next = await iterator.next()
    let trigger = try XCTUnwrap(next)
    XCTAssertFalse(trigger.overran)
    // Well inside the 100 ms frame interval: the first tick does not wait for a deadline.
    XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(50))
  }

  func testStallCatchesUpWithOneTickPerMissedInterval() async throws {
    let logger = CapturingLogger()
    var iterator = FrameCadence(framesPerSecond: 10, logger: logger).makeAsyncIterator()
    _ = await iterator.next()
    // A push that overran three and a half 100 ms frame budgets.
    try await Task.sleep(for: .milliseconds(350))

    // The catch-up ticks report `overran`; the first tick that waited for its deadline does not.
    // Counting the flags, not timing each tick, keeps the assertion off the wall clock.
    var overruns = 0
    for _ in 0..<5 {
      let next = await iterator.next()
      let trigger = try XCTUnwrap(next)
      if !trigger.overran { break }
      overruns += 1
    }
    // BUG: the clock advances one interval per tick, so a stall of N intervals is followed by N
    // back-to-back pushes of the same frame, each logged as its own overrun — flipped to a single
    // catch-up tick in the following commit.
    XCTAssertGreaterThanOrEqual(overruns, 3)
    XCTAssertEqual(logger.messages.compactMap { $0 as? String }.filter { $0.contains("exceeded budget") }.count, overruns)
  }
}
