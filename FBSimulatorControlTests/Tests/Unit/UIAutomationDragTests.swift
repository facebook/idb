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
    options: AccessibilityRequestOptions
  ) async throws -> AccessibilityElementsResponse {
    throw NotUnderTest()
  }

  func hitTest(
    at point: CGPoint,
    options: AccessibilityRequestOptions
  ) async throws -> AccessibilityElementsResponse? {
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
    direction: AccessibilityScrollDirection
  ) async throws {
    throw NotUnderTest()
  }

  var applicationFrame: CGRect?
  private(set) var framedQuery: AccessibilityElementQuery?

  func frame(_ query: AccessibilityElementQuery) async throws -> CGRect {
    framedQuery = query
    guard let applicationFrame else {
      throw NotUnderTest()
    }
    return applicationFrame
  }
}

/// A scroll bubbles from the element it names up to that element's scrollable container, so what an
/// untargeted scroll resolves to decides whether it can scroll at all: the application element has no
/// container above it and can never be scrolled, on either backend.
final class UIAutomationScrollTargetTests: XCTestCase {

  func testAnUntargetedScrollAimsAtTheCentreOfTheApplication() async throws {
    let automation = RecordingUIAutomation()
    automation.applicationFrame = CGRect(x: 0, y: 0, width: 420, height: 912)

    let target = try await automation.scrollTarget(for: .frontmost, backend: .accessibility)

    XCTAssertEqual(target, .point(CGPoint(x: 210, y: 456)))
    XCTAssertEqual(automation.framedQuery, .frontmost, "the centre has to come from the application's own frame")
  }

  /// An application that does not fill the screen is scrolled at its own centre, not the screen's.
  func testTheCentreIsTheApplicationsRatherThanTheScreens() async throws {
    let automation = RecordingUIAutomation()
    automation.applicationFrame = CGRect(x: 100, y: 200, width: 200, height: 400)

    let target = try await automation.scrollTarget(for: .frontmost, backend: .accessibility)

    XCTAssertEqual(target, .point(CGPoint(x: 200, y: 400)))
  }

  func testATargetedScrollIsLeftAlone() async throws {
    let automation = RecordingUIAutomation()
    automation.applicationFrame = CGRect(x: 0, y: 0, width: 420, height: 912)

    for query in [
      AccessibilityElementQuery.point(CGPoint(x: 12, y: 34)),
      .marker(value: "List", key: .label, depth: 10),
      .application(pid: 99),
    ] {
      let target = try await automation.scrollTarget(for: query, backend: .accessibility)
      XCTAssertEqual(target, query, "\(query) names an element already")
    }
    XCTAssertNil(automation.framedQuery, "a targeted scroll must not pay for a frame read it does not use")
  }

  // A degenerate frame would resolve to the origin, which is a corner of the screen and not the
  // application the caller asked to scroll.
  func testAnApplicationWithNoFrameIsRefusedRatherThanScrolledAtTheOrigin() async throws {
    let automation = RecordingUIAutomation()
    automation.applicationFrame = .zero

    do {
      _ = try await automation.scrollTarget(for: .frontmost, backend: .accessibility)
      XCTFail("a zero frame must not resolve to a point")
    } catch let error as UIAutomationError {
      guard case .frameUnavailable = error else {
        return XCTFail("expected frameUnavailable, got \(error)")
      }
    }
  }
}
