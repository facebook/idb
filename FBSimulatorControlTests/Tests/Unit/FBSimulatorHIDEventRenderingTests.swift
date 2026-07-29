/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorControl
// Matches the existing XCTest-based FBSimulatorControl unit suite (FBSimulatorHIDEventPanTests et al.).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Coverage of the `FBSimulatorHIDEvent` composite factories — the value-level decomposition of a
/// gesture into its ordered primitive sub-events (touch/button/keyboard/two-finger + delays). The
/// byte-level Indigo payloads are pinned by `FBSimulatorIndigoHIDTests`; the tvOS `pan`/`remoteButton`
/// factories by their own suites. This fills the gap for `tapAt`, `swipe`, `pinchAt`, and the
/// button/keyboard short-press factories, so the event model is a stable contract for the backends
/// that render it.
final class FBSimulatorHIDEventRenderingTests: XCTestCase {

  // MARK: - Helpers

  private func touches(_ event: FBSimulatorHIDEvent) throws -> [(FBSimulatorHIDDirection, Double, Double)] {
    try XCTUnwrap(event.subEvents).compactMap {
      if case let .touch(direction, x, y) = $0 { return (direction, x, y) }
      return nil
    }
  }

  private func twoFingerTouches(_ event: FBSimulatorHIDEvent) throws -> [(FBSimulatorHIDDirection, CGPoint, CGPoint)] {
    try XCTUnwrap(event.subEvents).compactMap {
      if case let .twoFingerTouch(direction, finger1, finger2) = $0 { return (direction, finger1, finger2) }
      return nil
    }
  }

  private func delayCount(_ event: FBSimulatorHIDEvent) throws -> Int {
    try XCTUnwrap(event.subEvents).filter {
      if case .delay = $0 { return true }
      return false
    }.count
  }

  // MARK: - Tap

  func testTapLowersToDownUp() {
    XCTAssertEqual(
      FBSimulatorHIDEvent.tapAt(x: 12, y: 34),
      .composite([
        .touch(direction: .down, x: 12, y: 34),
        .touch(direction: .up, x: 12, y: 34),
      ]))
  }

  func testTapWithDurationInsertsDelayBetweenDownAndUp() {
    XCTAssertEqual(
      FBSimulatorHIDEvent.tapAt(x: 12, y: 34, duration: 0.5),
      .composite([
        .touch(direction: .down, x: 12, y: 34),
        .delay(0.5),
        .touch(direction: .up, x: 12, y: 34),
      ]))
  }

  // MARK: - Button / Keyboard

  func testShortButtonPressLowersToDownUp() {
    XCTAssertEqual(
      FBSimulatorHIDEvent.shortButtonPress(.homeButton),
      .composite([
        .button(direction: .down, button: .homeButton),
        .button(direction: .up, button: .homeButton),
      ]))
  }

  func testShortKeyPressLowersToDownUp() {
    XCTAssertEqual(
      FBSimulatorHIDEvent.shortKeyPress(0x04),
      .composite([
        .keyboard(direction: .down, keyCode: 0x04),
        .keyboard(direction: .up, keyCode: 0x04),
      ]))
  }

  func testShortKeyPressSequencePressesEachKeyInOrder() {
    XCTAssertEqual(
      FBSimulatorHIDEvent.shortKeyPressSequence([0x04, 0x05, 0x06]),
      .composite([
        .keyboard(direction: .down, keyCode: 0x04),
        .keyboard(direction: .up, keyCode: 0x04),
        .keyboard(direction: .down, keyCode: 0x05),
        .keyboard(direction: .up, keyCode: 0x05),
        .keyboard(direction: .down, keyCode: 0x06),
        .keyboard(direction: .up, keyCode: 0x06),
      ]))
  }

  func testShortKeyPressSequenceEmptyIsEmptyComposite() {
    XCTAssertEqual(FBSimulatorHIDEvent.shortKeyPressSequence([]), .composite([]))
  }

  // MARK: - Swipe

  // A vertical swipe of distance 100 with delta 10 -> 10 steps. The factory emits (steps + 1)
  // interpolated touch-downs, a duplicated final touch-down (the anti-inertial-scroll guard), and a
  // terminating touch-up; a delay follows every touch-down except the final up.
  func testSwipeInterpolatesDownsThenLiftsUp() throws {
    let swipe = FBSimulatorHIDEvent.swipe(100, yStart: 100, xEnd: 100, yEnd: 200, delta: 10, duration: 0.3)
    let touches = try touches(swipe)

    // (steps + 1) interpolated downs + 1 duplicated final down + 1 up.
    XCTAssertEqual(touches.count, 13, "11 interpolated downs + 1 duplicate final down + 1 up")
    XCTAssertEqual(touches.filter { $0.0 == .down }.count, 12)
    XCTAssertEqual(touches.filter { $0.0 == .up }.count, 1)
    // One delay per down (none after the final up).
    XCTAssertEqual(try delayCount(swipe), 12, "a delay follows each of the 12 downs")

    // Starts at the origin, ends lifting at the destination.
    let first = try XCTUnwrap(touches.first)
    XCTAssertEqual(first.0, .down)
    XCTAssertEqual(first.1, 100, accuracy: 1e-9)
    XCTAssertEqual(first.2, 100, accuracy: 1e-9)
    let last = try XCTUnwrap(touches.last)
    XCTAssertEqual(last.0, .up)
    XCTAssertEqual(last.1, 100, accuracy: 1e-9)
    XCTAssertEqual(last.2, 200, accuracy: 1e-9)

    // Interpolated y-coordinates are monotonically non-decreasing 100 -> 200; x is constant.
    let downYs = touches.filter { $0.0 == .down }.map(\.2)
    XCTAssertEqual(try XCTUnwrap(downYs.first), 100, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(downYs.last), 200, accuracy: 1e-9, "duplicated final down sits at the destination")
    XCTAssertEqual(downYs, downYs.sorted(), "monotonic progression toward the destination")
    XCTAssertTrue(touches.allSatisfy { abs($0.1 - 100) < 1e-9 }, "constant x for a vertical swipe")
  }

  func testSwipeNonPositiveDeltaUsesDefault() throws {
    // delta <= 0 falls back to DEFAULT_SWIPE_DELTA (10), so distance 100 still yields 10 steps.
    let withZero = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 0, yEnd: 100, delta: 0, duration: 0.3)
    let withDefault = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 0, yEnd: 100, delta: DEFAULT_SWIPE_DELTA, duration: 0.3)
    XCTAssertEqual(try touches(withZero).count, try touches(withDefault).count)
  }

  func testSwipeClampsStepsToAtLeastOne() throws {
    // A sub-delta distance must not divide to zero steps; it degrades to a single interpolated down.
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 1, yEnd: 0, delta: 10, duration: 0.1)
    // (1 + 1) interpolated downs + 1 duplicate final down + 1 up.
    XCTAssertEqual(try touches(swipe).filter { $0.0 == .down }.count, 3)
    XCTAssertEqual(try touches(swipe).filter { $0.0 == .up }.count, 1)
  }

  // MARK: - Pinch

  // A pinch-out from radius 50 to 100 (scale 2) with delta 10 -> 5 steps. Two fingers stay symmetric
  // about the center on the horizontal axis; the radius grows from start to end; the gesture is a
  // sequence of two-finger downs (initial + steps + duplicated final) terminated by a two-finger up.
  func testPinchOutIsSymmetricAndGrowsRadius() throws {
    let center = CGPoint(x: 200, y: 200)
    let pinch = FBSimulatorHIDEvent.pinchAt(x: center.x, y: center.y, scale: 2, duration: 0.3, radius: 50)
    let events = try twoFingerTouches(pinch)

    // initial down + 5 interpolated downs + 1 duplicated final down + 1 up.
    XCTAssertEqual(events.count, 8)
    XCTAssertEqual(events.map(\.0), [.down, .down, .down, .down, .down, .down, .down, .up])
    XCTAssertEqual(try delayCount(pinch), 7, "a delay follows every down")

    // Fingers are always symmetric about the center on the horizontal axis (y == centerY).
    for (_, f1, f2) in events {
      XCTAssertEqual(f1.x + f2.x, 2 * center.x, accuracy: 1e-9, "symmetric about centerX")
      XCTAssertEqual(f1.y, center.y, accuracy: 1e-9)
      XCTAssertEqual(f2.y, center.y, accuracy: 1e-9)
      XCTAssertLessThan(f1.x, f2.x, "finger1 is the left contact")
    }

    // Radius (half the finger separation) grows from the start radius to the end radius.
    let startRadius = (events.first!.2.x - center.x)
    let endRadius = (events.last!.2.x - center.x)
    XCTAssertEqual(startRadius, 50, accuracy: 1e-9)
    XCTAssertEqual(endRadius, 100, accuracy: 1e-9)
  }

  func testPinchInShrinksRadius() throws {
    let pinch = FBSimulatorHIDEvent.pinchAt(x: 200, y: 200, scale: 0.5, duration: 0.3, radius: 100)
    let events = try twoFingerTouches(pinch)
    let startRadius = events.first!.2.x - 200
    let endRadius = events.last!.2.x - 200
    XCTAssertEqual(startRadius, 100, accuracy: 1e-9)
    XCTAssertEqual(endRadius, 50, accuracy: 1e-9, "pinch-in ends at the smaller radius")
  }

  func testPinchClampsStepsToAtLeastTwo() throws {
    // scale 1 -> zero finger travel -> steps would divide to 0; the factory clamps to 2 interpolated
    // moves so the gesture is still a well-formed multi-sample pinch.
    let pinch = FBSimulatorHIDEvent.pinchAt(x: 200, y: 200, scale: 1, duration: 0.3, radius: 50)
    // initial down + 2 interpolated downs + 1 duplicated final down + 1 up.
    XCTAssertEqual(try twoFingerTouches(pinch).count, 5)
  }
}
