/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBSimulatorControl
import IDBGRPCSwift
import XCTest

final class DescribeMethodHandlerTests: XCTestCase {
  func testADisplaySurvivesTheWireInItsCurrentOrientation() throws {
    let display = SimulatorDisplay(
      uniqueID: "FA9C9507-0D45-4189-A7D6-A3335032D47B", name: "LCD-1", activity: .active, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: 2008, height: 2854), scale: 3, rotation: .clockwise)

    let decoded = try Idb_Display(serializedBytes: DescribeMethodHandler.display(display).serializedData())

    XCTAssertEqual(decoded.uniqueID, "FA9C9507-0D45-4189-A7D6-A3335032D47B")
    XCTAssertEqual(decoded.name, "LCD-1")
    XCTAssertTrue(decoded.active)
    XCTAssertTrue(decoded.integrated)
    XCTAssertEqual(decoded.width, 2854)
    XCTAssertEqual(decoded.height, 2008)
    XCTAssertEqual(decoded.density, 3)
  }

  func testAnInactiveExternalDisplayIsReportedAsSuch() {
    let display = SimulatorDisplay(
      uniqueID: "F774281A-0000-0000-0000-000000000000", name: "TVOut", activity: .inactive, isPrimary: false, isIntegrated: false,
      bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1, rotation: .upright)

    let described = DescribeMethodHandler.display(display)

    XCTAssertFalse(described.active)
    XCTAssertFalse(described.integrated)
    XCTAssertEqual(described.width, 1920)
    XCTAssertEqual(described.height, 1080)
  }

  func testADisplayWithoutAUsableSizeIsReportedWithNone() {
    let display = SimulatorDisplay(
      uniqueID: "F774281A-0000-0000-0000-000000000000", name: "TVOut", activity: .inactive, isPrimary: false, isIntegrated: false,
      bounds: CGRect(x: 0, y: 0, width: CGFloat.nan, height: -1), scale: 1, rotation: .upright)

    let described = DescribeMethodHandler.display(display)

    XCTAssertEqual(described.width, 0)
    XCTAssertEqual(described.height, 0)
  }
}
