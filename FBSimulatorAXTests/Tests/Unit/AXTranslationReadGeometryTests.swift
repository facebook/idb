/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorAX
import XCTest

final class AXTranslationReadGeometryTests: XCTestCase {

  // MARK: - Screen

  func testWithoutADisplayTheRootFramePlacesTheRead() {
    let screen = AXReadScreen(display: nil, rootFrame: CGRect(x: 0, y: 0, width: 402, height: 874))
    XCTAssertEqual(screen.bounds, CGRect(x: 0, y: 0, width: 402, height: 874))
    XCTAssertEqual(screen.info, AccessibilityScreenInfo(width: 402, height: 874))
  }

  func testADegenerateRootFrameReportsNoScreen() {
    let screen = AXReadScreen(display: nil, rootFrame: .zero)
    XCTAssertEqual(screen.bounds, .zero)
    XCTAssertNil(screen.info, "an unknown screen is reported as unknown, not zero-sized")
  }

  // MARK: - Remote content grid

  func testUnsetOptionsSampleTheWholeScreenEveryFiftyPoints() {
    let plan = AXRemoteContentPlan(
      AccessibilityRemoteContentOptions(gridStepSize: 0), screenBounds: CGRect(x: 0, y: 0, width: 200, height: 160))
    XCTAssertEqual(plan.region, CGRect(x: 0, y: 0, width: 200, height: 160))
    XCTAssertEqual(plan.stepSize, 50)
    XCTAssertEqual(plan.maxPoints, 0)
  }

  func testPointsRunRowByRowInsetOneStepFromEachEdge() {
    let plan = AXRemoteContentPlan(
      AccessibilityRemoteContentOptions(gridStepSize: 50, region: CGRect(x: 10, y: 20, width: 200, height: 160)),
      screenBounds: .zero)
    XCTAssertEqual(
      plan.points,
      [CGPoint(x: 60, y: 70), CGPoint(x: 110, y: 70), CGPoint(x: 60, y: 120), CGPoint(x: 110, y: 120)],
      "a point one step from the far edge is not sampled")
  }

  func testACapIsExhaustedOnceThatManyPointsAreVisited() {
    let capped = AXRemoteContentPlan(AccessibilityRemoteContentOptions(maxPoints: 2), screenBounds: .zero)
    XCTAssertFalse(capped.isExhausted(afterVisiting: 1))
    XCTAssertTrue(capped.isExhausted(afterVisiting: 2))
    let uncapped = AXRemoteContentPlan(AccessibilityRemoteContentOptions(), screenBounds: .zero)
    XCTAssertFalse(uncapped.isExhausted(afterVisiting: 10_000))
  }
}
