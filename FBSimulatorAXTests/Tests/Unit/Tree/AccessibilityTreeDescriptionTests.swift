/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorAX
import XCTest

final class AccessibilityTreeDescriptionTests: XCTestCase {

  private static func element(_ label: String) -> AccessibilityDocumentElement {
    var element = AccessibilityDocumentElement()
    element.label = .some(label)
    element.frame = .some(AccessibilityFrame(CGRect(x: 0, y: 0, width: 100, height: 100)))
    return element
  }

  private static let walked = ["General", "Privacy", "General Settings"].map(element)
  private static let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

  private static func options(match: String? = nil, coverage: Bool = false) -> AccessibilityRequestOptions {
    AccessibilityRequestOptions(collectFrameCoverage: coverage, match: match.flatMap { AccessibilityMatch(value: $0) })
  }

  func testTheRequestNarrowsWhatIsReportedAndNotWhatWasWalked() {
    let description = AccessibilityTreeDescription(walked: Self.walked, options: Self.options(match: "General"), screenBounds: Self.screen)
    XCTAssertEqual(description.walked.count, 3)
    XCTAssertEqual(description.reported.compactMap { $0.label ?? nil }, ["General", "General Settings"])
  }

  func testARefinementRunsOnlyOnWhatSurvivesNarrowing() async {
    var description = AccessibilityTreeDescription(walked: Self.walked, options: Self.options(match: "General"), screenBounds: Self.screen)
    var seen = 0
    await description.refineReported { elements in
      seen = elements.count
      return Array(elements.prefix(1))
    }
    XCTAssertEqual(seen, 2)
    XCTAssertEqual(description.reported.compactMap { $0.label ?? nil }, ["General"])
  }

  func testCoverageNeedsTheRequestAndAKnownScreen() {
    XCTAssertNil(AccessibilityTreeDescription(walked: Self.walked, options: Self.options(), screenBounds: Self.screen).coverage())
    XCTAssertNil(AccessibilityTreeDescription(walked: Self.walked, options: Self.options(coverage: true), screenBounds: nil).coverage())
    XCTAssertNotNil(
      AccessibilityTreeDescription(walked: Self.walked, options: Self.options(coverage: true), screenBounds: Self.screen).coverage())
  }

  func testTheNarrowingReportCountsDiscoveredElementsAsWalked() {
    let description = AccessibilityTreeDescription(walked: Self.walked, options: Self.options(match: "General"), screenBounds: Self.screen)
    XCTAssertEqual(description.narrowingReport().walked, 3)
    XCTAssertEqual(description.narrowingReport().matched, 2)

    let discovered = [Self.element("Web content")]
    let report = description.narrowingReport(reporting: description.reported + discovered, discovered: discovered)
    XCTAssertEqual(report.walked, 4)
    XCTAssertEqual(report.matched, 3)
  }
}
