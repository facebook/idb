/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBSimulatorControl
import Foundation
import GRPCCore
import IDBGRPCSwift
import Testing

@Suite
struct HidRequestTranslationTests {
  @Test
  func hingeAnglesSurviveTheWire() throws {
    for degrees in [0.0, 90.0, 135.5, 180.0] {
      let request = Idb_HIDEvent.with { $0.hinge.angle = degrees }
      guard case let .hinge(angle) = try HidMethodHandler.request(from: request) else {
        Issue.record("Expected a hinge request")
        return
      }
      #expect(angle.degrees == degrees)
    }
  }

  @Test
  func invalidAnglesAreInvalidArguments() {
    for degrees in [-1, 180.001, Double.nan, .infinity, -.infinity] {
      let request = Idb_HIDEvent.with { $0.hinge.angle = degrees }
      let error = #expect(throws: (any Error).self) { try HidMethodHandler.request(from: request) }
      #expect((error as? RPCError)?.code == .invalidArgument)
    }
  }

  @Test
  func orientationsKeepTheirNamesOnTheWire() throws {
    let expected: [(Idb_HIDEvent.HIDOrientationType, SimulatorHIDDeviceOrientation)] = [
      (.portrait, .portrait),
      (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeLeft),
      (.landscapeRight, .landscapeRight),
    ]
    for (wire, orientation) in expected {
      let request = Idb_HIDEvent.with { $0.orientation.orientation = wire }
      #expect(try HidMethodHandler.request(from: request) == .orientation(orientation))
    }
  }

  @Test
  func anUnrecognizedOrientationIsAnInvalidArgument() {
    let request = Idb_HIDEvent.with { $0.orientation.orientation = .UNRECOGNIZED(99) }
    let error = #expect(throws: (any Error).self) { try HidMethodHandler.request(from: request) }
    #expect((error as? RPCError)?.code == .invalidArgument)
  }

  @Test
  func buttonsKeepTheirNamesOnTheWire() throws {
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
        #expect(try HidMethodHandler.request(from: request) == .input(.button(direction: direction, button: button)))
      }
    }
  }

  @Test
  func anUnrecognizedButtonIsAnInvalidArgument() {
    let request = Idb_HIDEvent.with { $0.press.action.button.button = .UNRECOGNIZED(99) }
    let error = #expect(throws: (any Error).self) { try HidMethodHandler.request(from: request) }
    #expect((error as? RPCError)?.code == .invalidArgument)
  }

  @Test
  func shakeTranslatesToShake() throws {
    let request = Idb_HIDEvent.with { $0.shake = Idb_HIDEvent.HIDShake() }
    #expect(try HidMethodHandler.request(from: request) == .shake)
  }
}
