/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Coverage for the two halves of a drag that exist above any backend: what `FBDragOptions()` means,
/// and what the two-argument `drag(from:to:)` sends when a caller does not choose.
///
/// A default that drifts is silent — the gesture still runs, it just runs differently — so the values
/// are pinned here rather than left to whichever backend happens to read them.
final class FBUIAutomationDragTests: XCTestCase {

  // The press hold is what makes this a drag rather than a flick: iOS opens a drag session only once
  // the press clears its long-press threshold, so a shortened default silently turns every drag into
  // a swipe.
  func testTheDefaultsAreTheDocumentedDrag() {
    let options = FBDragOptions()
    XCTAssertEqual(options.pressDuration, 0.5)
    XCTAssertEqual(options.duration, 0.5)
    XCTAssertEqual(options.releaseDuration, 0.1)
    XCTAssertEqual(options.delta, FBSimulatorHIDEvent.defaultSwipeDelta)
  }

  func testEveryOptionCanBeChosen() {
    let options = FBDragOptions(pressDuration: 1, duration: 2, releaseDuration: 3, delta: 4)
    XCTAssertEqual(options.pressDuration, 1)
    XCTAssertEqual(options.duration, 2)
    XCTAssertEqual(options.releaseDuration, 3)
    XCTAssertEqual(options.delta, 4)
  }

  /// The convenience extension is the one place the defaults are applied on a caller's behalf. If it
  /// ever built its options any other way, `drag(from:to:)` and `drag(from:to:options:
  /// FBDragOptions())` would stop being the same gesture.
  func testTheTwoArgumentDragSendsTheDefaults() async throws {
    let automation = RecordingUIAutomation()
    try await automation.drag(from: .point(CGPoint(x: 1, y: 2)), to: .point(CGPoint(x: 3, y: 4)))

    let recorded = try XCTUnwrap(automation.recorded)
    XCTAssertEqual(recorded.source, .point(CGPoint(x: 1, y: 2)))
    XCTAssertEqual(recorded.destination, .point(CGPoint(x: 3, y: 4)))
    XCTAssertEqual(recorded.options, FBDragOptions())
  }
}

/// An `FBUIAutomation` that records the drag it was handed and refuses every other verb. Only the
/// forwarding is under test, so the reads have nothing to return.
private final class RecordingUIAutomation: FBUIAutomation, @unchecked Sendable {

  struct Drag: Equatable {
    let source: FBAccessibilityElementQuery
    let destination: FBAccessibilityElementQuery
    let options: FBDragOptions
  }

  private(set) var recorded: Drag?

  private struct NotUnderTest: Error {}

  func drag(
    from source: FBAccessibilityElementQuery,
    to destination: FBAccessibilityElementQuery,
    options: FBDragOptions
  ) async throws {
    recorded = Drag(source: source, destination: destination, options: options)
  }

  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    throw NotUnderTest()
  }

  func hitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse? {
    throw NotUnderTest()
  }

  func tap(_ query: FBAccessibilityElementQuery, options: FBTapOptions) async throws {
    throw NotUnderTest()
  }

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    throw NotUnderTest()
  }

  func wait(
    _ query: FBAccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    throw NotUnderTest()
  }

  func scroll(
    _ query: FBAccessibilityElementQuery,
    direction: FBAccessibilityScrollDirection
  ) async throws {
    throw NotUnderTest()
  }

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    throw NotUnderTest()
  }
}
