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
    let pan = FBSimulatorHIDEvent.pan(fromX: 0.5, fromY: 0.2, toX: 0.5, toY: 0.8, steps: 3, duration: 0.3)
    let subs = try XCTUnwrap(pan.subEvents, "pan should be a composite")

    let trackpads: [(FBSimulatorTrackpadPhase, CGPoint)] = subs.compactMap {
      if case let .trackpad(phase, point) = $0 { return (phase, point) }
      return nil
    }

    // began + (steps) changed + ended.
    XCTAssertEqual(trackpads.count, 5, "began + 3 changed + ended")
    XCTAssertEqual(trackpads.first?.0, .began)
    XCTAssertEqual(trackpads.first?.1, CGPoint(x: 0.5, y: 0.2), "began at the start point")
    XCTAssertEqual(trackpads.last?.0, .ended)
    XCTAssertEqual(trackpads.last?.1, CGPoint(x: 0.5, y: 0.8), "ended at the end point")
    XCTAssertEqual(Array(trackpads[1...3]).map(\.0), [.changed, .changed, .changed], "interior samples are changed")

    // A delay precedes each changed sample and the ended sample (steps + 1 delays).
    let delays = subs.filter {
      if case .delay = $0 { return true }
      return false
    }
    XCTAssertEqual(delays.count, 4, "steps + 1 interleaved delays")
  }

  func testPanClampsStepsToAtLeastOne() throws {
    // steps <= 0 must not trap; it degrades to a single changed sample.
    let pan = FBSimulatorHIDEvent.pan(fromX: 0, fromY: 0, toX: 1, toY: 1, steps: 0, duration: 0.1)
    let trackpads = try XCTUnwrap(pan.subEvents).filter {
      if case .trackpad = $0 { return true }
      return false
    }
    XCTAssertEqual(trackpads.count, 3, "began + 1 changed + ended")
  }
}
