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

  func testButtonsKeepTheirNamesOnTheWire() throws {
    let expected: [(Idb_HIDEvent.HIDButtonType, SimulatorHIDButton)] = [
      (.applePay, .applePay),
      (.home, .homeButton),
      (.lock, .lock),
      (.sideButton, .sideButton),
      (.siri, .siri),
      (.playPause, .playPause),
      (.volumeUp, .volumeUp),
      (.volumeDown, .volumeDown),
      (.eject, .eject),
    ]
    for (wire, button) in expected {
      for (wireDirection, direction) in [(Idb_HIDEvent.HIDDirection.down, SimulatorHIDDirection.down), (.up, .up)] {
        let request = Idb_HIDEvent.with {
          $0.press.action.button.button = wire
          $0.press.direction = wireDirection
        }
        XCTAssertEqual(try HidMethodHandler.request(from: request), .input(.button(direction: direction, button: button)))
      }
    }
  }

  func testAnUnrecognizedButtonIsAnInvalidArgument() {
    let request = Idb_HIDEvent.with { $0.press.action.button.button = .UNRECOGNIZED(99) }
    XCTAssertThrowsError(try HidMethodHandler.request(from: request)) { error in
      XCTAssertEqual((error as? RPCError)?.code, .invalidArgument)
    }
  }

  func testTouchesAndSwipesKeepTheirEdgeOnTheWire() throws {
    let expected: [(Idb_HIDEvent.HIDEdge, SimulatorHIDEdge)] = [
      (.noEdge, .none),
      (.topEdge, .top),
      (.leftEdge, .left),
      (.bottomEdge, .bottom),
      (.rightEdge, .right),
    ]
    for (wire, edge) in expected {
      let touch = Idb_HIDEvent.with {
        $0.press.action.touch.point = Idb_Point.with { $0.x = 1; $0.y = 2 }
        $0.press.action.touch.edge = wire
        $0.press.direction = .down
      }
      XCTAssertEqual(
        try HidMethodHandler.request(from: touch), .input(.touch(direction: .down, x: 1, y: 2, edge: edge)))

      let swipe = Idb_HIDEvent.with {
        $0.swipe.start = Idb_Point.with { $0.x = 1; $0.y = 2 }
        $0.swipe.end = Idb_Point.with { $0.x = 3; $0.y = 4 }
        $0.swipe.delta = 1
        $0.swipe.duration = 0.5
        $0.swipe.edge = wire
      }
      XCTAssertEqual(
        try HidMethodHandler.request(from: swipe),
        .input(.swipe(1, yStart: 2, xEnd: 3, yEnd: 4, delta: 1, duration: 0.5, edge: edge)))
    }
  }

  func testAnUnrecognizedEdgeIsAnInvalidArgument() {
    let request = Idb_HIDEvent.with { $0.press.action.touch.edge = .UNRECOGNIZED(99) }
    XCTAssertThrowsError(try HidMethodHandler.request(from: request)) { error in
      XCTAssertEqual((error as? RPCError)?.code, .invalidArgument)
    }
  }

  func testShakeTranslatesToShake() throws {
    let request = Idb_HIDEvent.with { $0.shake = Idb_HIDEvent.HIDShake() }
    XCTAssertEqual(try HidMethodHandler.request(from: request), .shake)
  }
}
