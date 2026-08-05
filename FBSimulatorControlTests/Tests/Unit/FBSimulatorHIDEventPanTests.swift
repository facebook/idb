/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorControl
// Matches the existing XCTest-based FBSimulatorControl unit suite (FBSimulatorHIDRemoteButtonTests et al.).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Coverage of `FBSimulatorHIDEvent.pan(...)` — the tvOS trackpad pan factory that expands a
/// start→end drag into a phased began → changed×steps → ended gesture with interleaved delays.
final class FBSimulatorHIDEventPanTests: XCTestCase {

  func testPanExpandsToPhasedGesture() throws {
    let from = try XCTUnwrap(FBSimulatorTrackpadPoint(x: 0.5, y: 0.2))
    let to = try XCTUnwrap(FBSimulatorTrackpadPoint(x: 0.5, y: 0.8))
    let pan = FBSimulatorHIDEvent.pan(from: from, to: to, steps: 3, duration: 0.3)
    let subs = try XCTUnwrap(pan.subEvents, "pan should be a composite")

    let trackpads: [(FBSimulatorTrackpadPhase, FBSimulatorTrackpadPoint)] = subs.compactMap {
      if case let .trackpad(phase, point) = $0 { return (phase, point) }
      return nil
    }

    // began + (steps) changed + ended.
    XCTAssertEqual(trackpads.count, 5, "began + 3 changed + ended")
    XCTAssertEqual(trackpads.first?.0, .began)
    XCTAssertEqual(trackpads.first?.1, from, "began at the start point")
    XCTAssertEqual(trackpads.last?.0, .ended)
    XCTAssertEqual(trackpads.last?.1, to, "ended at the end point")
    XCTAssertEqual(Array(trackpads[1...3]).map(\.0), [.changed, .changed, .changed], "interior samples are changed")

    // A delay precedes each changed sample and the ended sample (steps + 1 delays).
    let delays = subs.filter {
      if case .delay = $0 { return true }
      return false
    }
    XCTAssertEqual(delays.count, 4, "steps + 1 interleaved delays")
  }

  // The trackpad surface is absolute-normalized, and now says so in the type. Screen coordinates used
  // to pass straight through `pan` — it took bare `Double`s and wrapped them in a `CGPoint`, the same
  // type `.twoFingerTouch` uses for screen points — and landed wherever the daemon put them. They can
  // no longer be built, so `pan` cannot be handed them.
  func testTrackpadPointRejectsCoordinatesOutsideTheSurface() throws {
    XCTAssertNil(FBSimulatorTrackpadPoint(x: 100, y: 200), "screen coordinates are not surface coordinates")
    XCTAssertNil(FBSimulatorTrackpadPoint(x: 0.5, y: 1.5), "one axis outside the unit square is enough")
    XCTAssertNil(FBSimulatorTrackpadPoint(x: -0.1, y: 0.5), "and so is a negative one")

    XCTAssertNotNil(FBSimulatorTrackpadPoint(x: 0, y: 0), "the corners are on the surface")
    XCTAssertNotNil(FBSimulatorTrackpadPoint(x: 1, y: 1), "including the far one")
  }

  func testPanClampsStepsToAtLeastOne() throws {
    // steps <= 0 must not trap; it degrades to a single changed sample.
    let from = try XCTUnwrap(FBSimulatorTrackpadPoint(x: 0, y: 0))
    let to = try XCTUnwrap(FBSimulatorTrackpadPoint(x: 1, y: 1))
    let pan = FBSimulatorHIDEvent.pan(from: from, to: to, steps: 0, duration: 0.1)
    let trackpads = try XCTUnwrap(pan.subEvents).filter {
      if case .trackpad = $0 { return true }
      return false
    }
    XCTAssertEqual(trackpads.count, 3, "began + 1 changed + ended")
  }
}
