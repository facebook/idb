/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBUIAutomationTests: XCTestCase {

  // The remote backend's pid-probe anchor is the screen centre in points: marker and whole-tree
  // reads probe it to discover the frontmost app's pid. The arithmetic is a pure function so it is
  // unit-testable without a target.

  func testAnchorPointIsScreenCentreInPoints() {
    let anchor = FBSimulatorRemoteAutomation.anchorPoint(widthPixels: 828, heightPixels: 1792, scale: 2)
    XCTAssertEqual(anchor.x, 207, accuracy: 0.001)
    XCTAssertEqual(anchor.y, 448, accuracy: 0.001)
  }

  func testAnchorPointHonoursScale() {
    let anchor = FBSimulatorRemoteAutomation.anchorPoint(widthPixels: 1206, heightPixels: 2622, scale: 3)
    XCTAssertEqual(anchor.x, 201, accuracy: 0.001)
    XCTAssertEqual(anchor.y, 437, accuracy: 0.001)
  }

  func testAnchorPointGuardsAgainstZeroScale() {
    let anchor = FBSimulatorRemoteAutomation.anchorPoint(widthPixels: 400, heightPixels: 800, scale: 0)
    XCTAssertEqual(anchor.x, 200, accuracy: 0.001)
    XCTAssertEqual(anchor.y, 400, accuracy: 0.001)
  }
}
