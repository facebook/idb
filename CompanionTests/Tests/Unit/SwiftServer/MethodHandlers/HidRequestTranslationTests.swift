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
      guard case let .hinge(angle) = try HidMethodHandler.request(from: request) else {
        return XCTFail("Expected a hinge request")
      }
      XCTAssertEqual(angle.degrees, degrees)
    }
  }

  func testInvalidAnglesAreInvalidArguments() {
    for degrees in [-1, 180.001, Double.nan, .infinity, -.infinity] {
      let request = Idb_HIDEvent.with { $0.hinge.angle = degrees }
      XCTAssertThrowsError(try HidMethodHandler.request(from: request)) { error in
        XCTAssertEqual((error as? RPCError)?.code, .invalidArgument)
      }
    }
  }

  func testOrientationsKeepTheirNamesOnTheWire() throws {
    let expected: [(Idb_HIDEvent.HIDOrientationType, SimulatorHIDDeviceOrientation)] = [
      (.portrait, .portrait),
      (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeLeft),
      (.landscapeRight, .landscapeRight),
    ]
    for (wire, orientation) in expected {
      let request = Idb_HIDEvent.with { $0.orientation.orientation = wire }
      XCTAssertEqual(try HidMethodHandler.request(from: request), .orientation(orientation))
    }
  }

  func testAnUnrecognizedOrientationIsAnInvalidArgument() {
    let request = Idb_HIDEvent.with { $0.orientation.orientation = .UNRECOGNIZED(99) }
    XCTAssertThrowsError(try HidMethodHandler.request(from: request)) { error in
      XCTAssertEqual((error as? RPCError)?.code, .invalidArgument)
    }
  }

  func testShakeTranslatesToShake() throws {
    let request = Idb_HIDEvent.with { $0.shake = Idb_HIDEvent.HIDShake() }
    XCTAssertEqual(try HidMethodHandler.request(from: request), .shake)
  }
}
