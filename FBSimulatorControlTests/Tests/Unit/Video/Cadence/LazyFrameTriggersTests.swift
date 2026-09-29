/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

/// How the lazy cadence paces the triggers its signals produce. Timed where the pacing happens, as
/// each trigger is handed out, so the push work that follows a trigger does not blur the interval.
final class LazyFrameTriggersTests: XCTestCase {

  // The pacing waits on the uptime clock, which is what `SuspendingClock` reads.
  private let clock = SuspendingClock()

  func testAFirstSignalIsNotHeld() async throws {
    let triggers = LazyFrameTriggers(maximumFramesPerSecond: 10)
    var iterator = triggers.makeAsyncIterator()
    triggers.signalFrameRendered()

    let started = clock.now
    let next = await iterator.next()

    XCTAssertNotNil(next)
    // Well inside the 100 ms interval.
    XCTAssertLessThan(clock.now - started, .milliseconds(50))
  }

  func testASignalSoonerThanTheIntervalIsHeldUntilTheIntervalHasPassed() async throws {
    let triggers = LazyFrameTriggers(maximumFramesPerSecond: 10)
    var iterator = triggers.makeAsyncIterator()
    triggers.signalFrameRendered()
    _ = await iterator.next()
    let first = clock.now

    triggers.signalFrameRendered()
    let next = await iterator.next()

    XCTAssertNotNil(next, "a held signal is still delivered")
    // `first` is read just after the iterator recorded the trigger, so the gap measured from it
    // can fall short of the interval by that instant; a millisecond covers it.
    XCTAssertGreaterThanOrEqual(clock.now - first, .milliseconds(99))
  }

  func testSignalsWithinOneIntervalCoalesceIntoOneTrigger() async throws {
    let triggers = LazyFrameTriggers(maximumFramesPerSecond: 10)
    var iterator = triggers.makeAsyncIterator()
    triggers.signalFrameRendered()
    _ = await iterator.next()

    triggers.signalFrameRendered()
    triggers.signalFrameRendered()
    triggers.signalFrameRendered()
    let held = await iterator.next()
    // A finished stream still hands out whatever it buffered before ending.
    triggers.finish()
    let afterFinish = await iterator.next()

    XCTAssertNotNil(held)
    XCTAssertNil(afterFinish, "three signals within one interval must produce one trigger")
  }

  func testASignalAfterTheIntervalIsNotHeld() async throws {
    let triggers = LazyFrameTriggers(maximumFramesPerSecond: 10)
    var iterator = triggers.makeAsyncIterator()
    triggers.signalFrameRendered()
    _ = await iterator.next()
    try await Task.sleep(for: .milliseconds(150))

    triggers.signalFrameRendered()
    let started = clock.now
    _ = await iterator.next()

    XCTAssertLessThan(clock.now - started, .milliseconds(50))
  }
}
