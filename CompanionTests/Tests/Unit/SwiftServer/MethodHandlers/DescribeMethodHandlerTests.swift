/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import IDBGRPCSwift
import XCTest

final class DescribeMethodHandlerTests: XCTestCase {
  private struct Failure: Error {}

  func testADisplaySurvivesTheWire() throws {
    let display = TargetDisplayDescription(
      uniqueID: "FA9C9507-0D45-4189-A7D6-A3335032D47B", name: "LCD-1", isActive: true, isIntegrated: true, widthPixels: 2854,
      heightPixels: 2008, scale: 3)

    let decoded = try Idb_Display(serializedBytes: DescribeMethodHandler.display(display).serializedData())

    XCTAssertEqual(decoded.uniqueID, "FA9C9507-0D45-4189-A7D6-A3335032D47B")
    XCTAssertEqual(decoded.name, "LCD-1")
    XCTAssertTrue(decoded.active)
    XCTAssertTrue(decoded.integrated)
    XCTAssertEqual(decoded.width, 2854)
    XCTAssertEqual(decoded.height, 2008)
    XCTAssertEqual(decoded.density, 3)
  }

  func testATargetWithoutDiagnosticsIsDescribedWithEmptyOnes() throws {
    XCTAssertTrue(try DescribeMethodHandler.diagnostics(.unsupported).isEmpty)
  }

  func testDiagnosticsThatCannotBeReadFailTheDescription() {
    XCTAssertThrowsError(try DescribeMethodHandler.diagnostics(.failed(Failure())))
  }
}
