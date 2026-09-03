/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
// Matches the existing XCTest-based FBSimulatorControl unit suite (FBSimulatorHIDEventPanTests et al.).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Coverage of `FBSimulatorHIDEvent.drag(...)` — the press → travel → release → lift composite that
/// `swipe` cannot express, because it has one duration for three phases.
final class FBSimulatorHIDEventDragTests: XCTestCase {

  private func touches(_ event: FBSimulatorHIDEvent) throws -> [(FBSimulatorHIDDirection, Double, Double)] {
    try XCTUnwrap(event.subEvents, "drag should be a composite").compactMap {
      if case let .touch(direction, x, y) = $0 { return (direction, x, y) }
      return nil
    }
  }

  private func delays(_ event: FBSimulatorHIDEvent) throws -> [TimeInterval] {
    try XCTUnwrap(event.subEvents).compactMap {
      if case let .delay(interval) = $0 { return interval }
      return nil
    }
  }

  func testDragPressesTravelsAndLifts() throws {
    // 300 pt path at the default 10 pt delta: 30 interpolated samples.
    let drag = FBSimulatorHIDEvent.drag(
      100, yStart: 100, xEnd: 100, yEnd: 400, delta: 10,
      pressDuration: 0.5, duration: 0.6, releaseDuration: 0.1)
    let touches = try touches(drag)

    XCTAssertEqual(touches.count, 32, "the initial press, 30 interpolated samples, and the lift")
    XCTAssertEqual(touches.first?.0, .down)
    XCTAssertEqual(touches.first?.1, 100)
    XCTAssertEqual(touches.first?.2, 100, "the press lands on the source, before any travel")
    XCTAssertEqual(touches.dropFirst().dropLast().map(\.0), Array(repeating: .down, count: 30))
    XCTAssertEqual(touches.last?.0, .up)
    XCTAssertEqual(touches.last?.1, 100)
    XCTAssertEqual(touches.last?.2, 400, "the lift is at the destination")

    // Second sample onwards interpolate evenly, so the first move is one delta along the path.
    XCTAssertEqual(touches[1].2, 110, accuracy: 0.001)
  }

  func testDragDurationsAreAdditiveAndNamedPhasesAreDistinct() throws {
    let drag = FBSimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 40, delta: 10,
      pressDuration: 0.5, duration: 0.8, releaseDuration: 0.1)
    let delays = try delays(drag)

    XCTAssertEqual(delays.count, 6, "the press hold, one per sample, and the release hold")
    XCTAssertEqual(delays.first, 0.5, "the press hold is not divided across the samples")
    XCTAssertEqual(delays.last, 0.1, "the release hold is its own phase")
    XCTAssertEqual(delays.dropFirst().dropLast().reduce(0, +), 0.8, accuracy: 0.001, "travel takes `duration`")
    XCTAssertEqual(delays.reduce(0, +), 1.4, accuracy: 0.001, "and the three phases add up")
  }

  // The knob `swipe` does not have: on `swipe` the hold at the source is duration / (steps + 2), so
  // it shrinks as the path lengthens. The drag's press hold is fixed whatever the path is.
  func testPressHoldDoesNotShrinkWithPathLength() throws {
    let short = FBSimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 20, delta: 10,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)
    let long = FBSimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 600, delta: 10,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)

    XCTAssertEqual(try delays(short).first, 0.5)
    XCTAssertEqual(try delays(long).first, 0.5)

    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 0, yEnd: 600, delta: 10, duration: 0.5)
    let swipeHold = try XCTUnwrap(delays(swipe).first)
    XCTAssertLessThan(swipeHold, 0.05, "which is the whole reason drag exists")
  }

  func testDeltaAtOrAboveTheDistanceCollapsesToASingleSample() throws {
    let drag = FBSimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 300, delta: 300,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)

    // One move, straight to the destination — measured on device as a flick rather than a drag,
    // which is why the companion rejects it rather than delivering this.
    XCTAssertEqual(try touches(drag).count, 3, "press, one move, lift")
  }

  func testNonPositiveDeltaTakesTheSwipeDefault() throws {
    let explicit = FBSimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 100, delta: FBSimulatorHIDEvent.defaultSwipeDelta,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)

    for delta in [0.0, -1.0] {
      let defaulted = FBSimulatorHIDEvent.drag(
        0, yStart: 0, xEnd: 0, yEnd: 100, delta: delta,
        pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)
      XCTAssertEqual(defaulted, explicit, "delta \(delta) should sample at the default")
    }
  }

  func testZeroLengthDragStillPressesAndLifts() throws {
    // The companion rejects this, but the factory must not trap on a zero step count.
    let drag = FBSimulatorHIDEvent.drag(
      50, yStart: 50, xEnd: 50, yEnd: 50, delta: 10,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)
    let touches = try touches(drag)

    XCTAssertEqual(touches.count, 3)
    XCTAssertEqual(touches.map(\.0), [.down, .down, .up])
    XCTAssertTrue(touches.allSatisfy { $0.1 == 50 && $0.2 == 50 })
  }
}
