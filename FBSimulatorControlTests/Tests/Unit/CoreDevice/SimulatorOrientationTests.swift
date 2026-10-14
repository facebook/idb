/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing
import XPC

@Suite
struct SimulatorOrientationTests {
  @Test
  func writablePhysicalOrientationsMapToHID() throws {
    let cases: [(SimulatorDeviceOrientation, SimulatorHIDDeviceOrientation)] = [
      (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeLeft), (.landscapeRight, .landscapeRight),
    ]
    for (orientation, expected) in cases {
      #expect(try orientation.hidOrientation == expected)
    }
  }

  @Test
  func unwritablePhysicalOrientationsAreInvalidArguments() throws {
    for orientation: SimulatorDeviceOrientation in [.unknown, .faceUp, .faceDown] {
      let error = #expect(throws: (any Error).self) { try orientation.hidOrientation }
      guard let error else { continue }
      guard case SimulatorOrientationError.unwritable(orientation) = error else {
        Issue.record("Expected an unwritable orientation, got \(error)")
        continue
      }
    }
  }

  @Test
  func physicalPurpleEncodingPreservesLegacyHIDValues() {
    #expect(SimulatorHIDDeviceOrientation.landscapeLeft.rawValue == 4)
    #expect(SimulatorHIDDeviceOrientation.landscapeRight.rawValue == 3)
    let cases: [(SimulatorHIDDeviceOrientation, Int32)] = [
      (.portrait, 1), (.portraitUpsideDown, 2), (.landscapeLeft, 3), (.landscapeRight, 4),
    ]
    for (orientation, expected) in cases {
      #expect(orientation.physicalPurpleOrientation.rawValue == expected)
    }
  }

  @Test
  func theVendorBackendIgnoresTheConvention() {
    for orientation in SimulatorHIDDeviceOrientation.allCases {
      for convention in [SimulatorOrientationConvention.device, .interface] {
        #expect(OrientationWrite(orientation, convention: convention, backend: .vendorHID) == .vendorHID(orientation))
      }
    }
  }

  @Test
  func purpleSwapsLandscapeOnlyForTheDeviceConvention() {
    let device: [(SimulatorHIDDeviceOrientation, SimulatorHIDDeviceOrientation)] = [
      (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeRight), (.landscapeRight, .landscapeLeft),
    ]
    for (orientation, sent) in device {
      #expect(OrientationWrite(orientation, convention: .device, backend: .purple) == .purple(sent))
    }
    for orientation in SimulatorHIDDeviceOrientation.allCases {
      #expect(OrientationWrite(orientation, convention: .interface, backend: .purple) == .purple(orientation))
    }
  }

  @Test
  func motionStatePreservesPhysicalDirectionsAndFlatStates() throws {
    let orientations: [SimulatorDeviceOrientation] = [.unknown, .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight, .faceUp, .faceDown]
    for (value, orientation) in orientations.enumerated() {
      #expect(try SimulatorOrientationCommands.decodeMotionState("{\"orientation\":\(value)}") == orientation)
    }
  }

  @Test
  func invalidMotionStateDoesNotDefaultToPortrait() {
    for output in ["", "{}", "null", "[]", "{\"orientation\":null}", "{\"orientation\":true}", "{\"orientation\":\"1\"}", "{\"orientation\":1.5}", "{\"orientation\":-1}", "{\"orientation\":7}"] {
      #expect(throws: (any Error).self, "\(output)") { try SimulatorOrientationCommands.decodeMotionState(output) }
    }
  }

  @Test
  func legacyRequestUsesCurrentOrientation() throws {
    let request = try SimulatorOrientationProtocol.request()
    #expect(String(cString: xpc_dictionary_get_string(request, "messageType")!) == "OrientationRequest")
    #expect(String(cString: xpc_dictionary_get_string(request, "featureIdentifier")!) == SimulatorOrientationProtocol.service)
    let payload = try #require(xpc_dictionary_get_value(request, "payload"))
    let current = try #require(xpc_dictionary_get_value(payload, "currentOrientation"))
    #expect(xpc_get_type(current) == XPC_TYPE_DICTIONARY)
    #expect(xpc_dictionary_get_count(current) == 0)
  }

  @Test
  func legacyReplyPreservesAllPhysicalOrientations() throws {
    for orientation in SimulatorDeviceOrientation.allCases {
      let reply = SimulatorCoreDevice.dictionary(["currentDeviceOrientation": xpc_string_create(orientation.rawValue)])
      #expect(try SimulatorOrientationProtocol.orientation(reply) == orientation)
    }
  }

  @Test
  func invalidLegacyRepliesFail() {
    for reply in [xpc_null_create(), xpc_string_create("portrait"), SimulatorCoreDevice.dictionary([:])] {
      #expect(throws: (any Error).self) { try SimulatorOrientationProtocol.orientation(reply) }
    }
    for value in [xpc_null_create(), xpc_int64_create(1), xpc_bool_create(true), xpc_string_create("futureOrientation")] {
      #expect(throws: (any Error).self) { try SimulatorOrientationProtocol.orientation(SimulatorCoreDevice.dictionary(["currentDeviceOrientation": value])) }
    }
  }
}
