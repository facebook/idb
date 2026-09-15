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

final class UIAutomationDragTests: XCTestCase {

  // The press hold is what makes this a drag rather than a flick: iOS opens a drag session only once
  // the press clears its long-press threshold, so a shortened default silently turns every drag into
  // a swipe.
  func testTheDefaultsAreTheDocumentedDrag() {
    let options = DragOptions()
    XCTAssertEqual(options.pressDuration, 0.5)
    XCTAssertEqual(options.duration, 0.5)
    XCTAssertEqual(options.releaseDuration, 0.1)
    XCTAssertEqual(options.delta, SimulatorHIDEvent.defaultSwipeDelta)
  }

  func testTheTwoArgumentDragSendsTheDefaults() async throws {
    let automation = RecordingUIAutomation()
    try await automation.drag(from: .point(CGPoint(x: 1, y: 2)), to: .point(CGPoint(x: 3, y: 4)))

    let recorded = try XCTUnwrap(automation.recorded)
    XCTAssertEqual(recorded.source, .point(CGPoint(x: 1, y: 2)))
    XCTAssertEqual(recorded.destination, .point(CGPoint(x: 3, y: 4)))
    XCTAssertEqual(recorded.options, DragOptions())
  }
}

private final class RecordingUIAutomation: UIAutomation, @unchecked Sendable {

  struct Drag: Equatable {
    let source: AccessibilityElementQuery
    let destination: AccessibilityElementQuery
    let options: DragOptions
  }

  private(set) var recorded: Drag?

  private struct NotUnderTest: Error {}

  func drag(
    from source: AccessibilityElementQuery,
    to destination: AccessibilityElementQuery,
    options: DragOptions
  ) async throws {
    recorded = Drag(source: source, destination: destination, options: options)
  }

  func describe(
    _ query: AccessibilityElementQuery,
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

  func tap(_ query: AccessibilityElementQuery, options: TapOptions) async throws {
    throw NotUnderTest()
  }

  func setValue(_ value: String, for query: AccessibilityElementQuery) async throws {
    throw NotUnderTest()
  }

  func wait(
    _ query: AccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    throw NotUnderTest()
  }

  func scroll(
    _ query: AccessibilityElementQuery,
    direction: FBAccessibilityScrollDirection
  ) async throws {
    throw NotUnderTest()
  }

  func frame(_ query: AccessibilityElementQuery) async throws -> CGRect {
    throw NotUnderTest()
  }
}
