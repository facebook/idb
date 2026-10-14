/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
// Matches the existing XCTest-based FBSimulatorControl unit suite (SimulatorHIDEventPanTests et al.).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import Foundation
import Testing

/// Coverage of `SimulatorHIDEvent.drag(...)` — the press → travel → release → lift composite that
/// `swipe` cannot express, because it has one duration for three phases.
@Suite
struct SimulatorHIDEventDragTests {

  private func touches(_ event: SimulatorHIDEvent) throws -> [(SimulatorHIDDirection, Double, Double)] {
    try #require(event.subEvents, "drag should be a composite").compactMap {
      if case let .touch(direction, x, y, _) = $0 { return (direction, x, y) }
      return nil
    }
  }

  private func delays(_ event: SimulatorHIDEvent) throws -> [TimeInterval] {
    try #require(event.subEvents).compactMap {
      if case let .delay(interval) = $0 { return interval }
      return nil
    }
  }

  @Test
  func dragPressesTravelsAndLifts() throws {
    // 300 pt path at the default 10 pt delta: 30 interpolated samples.
    let drag = SimulatorHIDEvent.drag(
      100, yStart: 100, xEnd: 100, yEnd: 400, delta: 10,
      pressDuration: 0.5, duration: 0.6, releaseDuration: 0.1)
    let touches = try touches(drag)

    #expect(touches.count == 32, "the initial press, 30 interpolated samples, and the lift")
    #expect(touches.first?.0 == .down)
    #expect(touches.first?.1 == 100)
    #expect(touches.first?.2 == 100, "the press lands on the source, before any travel")
    #expect(touches.dropFirst().dropLast().map(\.0) == Array(repeating: .down, count: 30))
    #expect(touches.last?.0 == .up)
    #expect(touches.last?.1 == 100)
    #expect(touches.last?.2 == 400, "the lift is at the destination")

    // Second sample onwards interpolate evenly, so the first move is one delta along the path.
    #expect(abs(touches[1].2 - 110) <= 0.001)
  }

  @Test
  func dragDurationsAreAdditiveAndNamedPhasesAreDistinct() throws {
    let drag = SimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 40, delta: 10,
      pressDuration: 0.5, duration: 0.8, releaseDuration: 0.1)
    let delays = try delays(drag)

    #expect(delays.count == 6, "the press hold, one per sample, and the release hold")
    #expect(delays.first == 0.5, "the press hold is not divided across the samples")
    #expect(delays.last == 0.1, "the release hold is its own phase")
    #expect(abs(delays.dropFirst().dropLast().reduce(0, +) - 0.8) <= 0.001, "travel takes `duration`")
    #expect(abs(delays.reduce(0, +) - 1.4) <= 0.001, "and the three phases add up")
  }

  // The knob `swipe` does not have: on `swipe` the hold at the source is duration / (steps + 2), so
  // it shrinks as the path lengthens. The drag's press hold is fixed whatever the path is.
  @Test
  func pressHoldDoesNotShrinkWithPathLength() throws {
    let short = SimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 20, delta: 10,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)
    let long = SimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 600, delta: 10,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)

    #expect(try delays(short).first == 0.5)
    #expect(try delays(long).first == 0.5)

    let swipe = SimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 0, yEnd: 600, delta: 10, duration: 0.5)
    let swipeHold = try #require(delays(swipe).first)
    #expect(swipeHold < 0.05, "which is the whole reason drag exists")
  }

  @Test
  func deltaAtOrAboveTheDistanceCollapsesToASingleSample() throws {
    let drag = SimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 300, delta: 300,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)

    // One move, straight to the destination — measured on device as a flick rather than a drag,
    // which is why the companion rejects it rather than delivering this.
    #expect(try touches(drag).count == 3, "press, one move, lift")
  }

  @Test
  func nonPositiveDeltaTakesTheSwipeDefault() throws {
    let explicit = SimulatorHIDEvent.drag(
      0, yStart: 0, xEnd: 0, yEnd: 100, delta: SimulatorHIDEvent.defaultSwipeDelta,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)

    for delta in [0.0, -1.0] {
      let defaulted = SimulatorHIDEvent.drag(
        0, yStart: 0, xEnd: 0, yEnd: 100, delta: delta,
        pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)
      #expect(defaulted == explicit, "delta \(delta) should sample at the default")
    }
  }

  @Test
  func zeroLengthDragStillPressesAndLifts() throws {
    // The companion rejects this, but the factory must not trap on a zero step count.
    let drag = SimulatorHIDEvent.drag(
      50, yStart: 50, xEnd: 50, yEnd: 50, delta: 10,
      pressDuration: 0.5, duration: 0.5, releaseDuration: 0.1)
    let touches = try touches(drag)

    #expect(touches.count == 3)
    #expect(touches.map(\.0) == [.down, .down, .up])
    #expect(touches.allSatisfy { $0.1 == 50 && $0.2 == 50 })
  }
}
