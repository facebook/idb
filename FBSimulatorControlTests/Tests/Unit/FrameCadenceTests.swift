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

  func testTicksLandOnTheirDeadlines() async throws {
    // Timer coalescing is a property of the host and the process's QoS; where a plain sleep already
    // wakes on time there is nothing to observe.
    var probe: [Duration] = []
    for _ in 0..<5 {
      let started = ContinuousClock.now
      try await Task.sleep(for: .milliseconds(10), tolerance: .zero)
      probe.append(ContinuousClock.now - started - .milliseconds(10))
    }
    probe.sort()
    try XCTSkipUnless(probe[2] >= .milliseconds(10), "this host does not coalesce Task.sleep (median lateness \(probe[2]))")

    var iterator = FrameCadence(framesPerSecond: 20).makeAsyncIterator()
    _ = await iterator.next()
    var lateness: [Duration] = []
    var expected = ContinuousClock.now
    for _ in 0..<10 {
      expected += .milliseconds(50)
      _ = await iterator.next()
      lateness.append(ContinuousClock.now - expected)
    }
    lateness.sort()
    // BUG: the clock waits with Task.sleep, which the scheduler coalesces, so on such a host every
    // tick lands 25–40 ms late — most of a 30 fps frame budget. Flipped to a median under 10 ms in
    // the following commit. The median, so one preempted tick does not decide the test.
    XCTAssertGreaterThanOrEqual(lateness[5], .milliseconds(10), "median tick lateness \(lateness[5])")
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
