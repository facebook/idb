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
    var iterator = FrameCadence(framesPerSecond: 10).makeAsyncIterator()
    let started = ContinuousClock.now
    let next = await iterator.next()
    let trigger = try XCTUnwrap(next)
    XCTAssertFalse(trigger.overran)
    // Well inside the 100 ms frame interval: the first tick does not wait for a deadline.
    XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(50))
  }

  func testStallCatchesUpWithASingleTick() async throws {
    var iterator = FrameCadence(framesPerSecond: 10).makeAsyncIterator()
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
    XCTAssertEqual(overruns, 1)
  }
}
