/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBSimulatorControl
import GRPCCore
import IDBGRPCSwift
import XCTest

final class HidRequestTranslationTests: XCTestCase {
  func testHingeAnglesSurviveTheWire() throws {
    for degrees in [0.0, 90.0, 135.5, 180.0] {
      let request = Idb_HIDEvent.with { $0.hinge.angle = degrees }
      guard case let .hinge(angle) = try HidMethodHandler.fbSimulatorHIDEvent(from: request) else {
        return XCTFail("Expected hinge input")
      }
      XCTAssertEqual(angle.degrees, degrees)
    }
  }

  func testInvalidAnglesAreInvalidArguments() {
    for degrees in [-1, 180.001, Double.nan, .infinity, -.infinity] {
      let request = Idb_HIDEvent.with { $0.hinge.angle = degrees }
      XCTAssertThrowsError(try HidMethodHandler.fbSimulatorHIDEvent(from: request)) { error in
        XCTAssertEqual((error as? RPCError)?.code, .invalidArgument)
      }
    }
  }
}
