/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest
import XPC

final class SimulatorOrientationTests: XCTestCase {
  func testWritablePhysicalOrientationsMapToHID() throws {
    let cases: [(SimulatorDeviceOrientation, SimulatorHIDDeviceOrientation)] = [
      (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeLeft), (.landscapeRight, .landscapeRight),
    ]
    for (orientation, expected) in cases {
      XCTAssertEqual(try orientation.hidOrientation, expected)
    }
  }

  func testUnwritablePhysicalOrientationsAreInvalidArguments() {
    for orientation: SimulatorDeviceOrientation in [.unknown, .faceUp, .faceDown] {
      XCTAssertThrowsError(try orientation.hidOrientation) { error in
        guard case SimulatorOrientationError.unwritable(orientation) = error else {
          return XCTFail("Expected an unwritable orientation, got \(error)")
        }
      }
    }
  }

  func testPhysicalPurpleEncodingPreservesLegacyHIDValues() {
    XCTAssertEqual(SimulatorHIDDeviceOrientation.landscapeLeft.rawValue, 4)
    XCTAssertEqual(SimulatorHIDDeviceOrientation.landscapeRight.rawValue, 3)
    let cases: [(SimulatorHIDDeviceOrientation, Int32)] = [
      (.portrait, 1), (.portraitUpsideDown, 2), (.landscapeLeft, 3), (.landscapeRight, 4),
    ]
    for (orientation, expected) in cases {
      XCTAssertEqual(orientation.physicalPurpleOrientation.rawValue, expected)
    }
  }

  func testTheVendorBackendIgnoresTheConvention() {
    for orientation in SimulatorHIDDeviceOrientation.allCases {
      for convention in [SimulatorOrientationConvention.device, .interface] {
        XCTAssertEqual(OrientationWrite(orientation, convention: convention, backend: .vendorHID), .vendorHID(orientation))
      }
    }
  }

  func testPurpleSwapsLandscapeOnlyForTheDeviceConvention() {
    let device: [(SimulatorHIDDeviceOrientation, SimulatorHIDDeviceOrientation)] = [
      (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeRight), (.landscapeRight, .landscapeLeft),
    ]
    for (orientation, sent) in device {
      XCTAssertEqual(OrientationWrite(orientation, convention: .device, backend: .purple), .purple(sent))
    }
    for orientation in SimulatorHIDDeviceOrientation.allCases {
      XCTAssertEqual(OrientationWrite(orientation, convention: .interface, backend: .purple), .purple(orientation))
    }
  }

  func testMotionStatePreservesPhysicalDirectionsAndFlatStates() throws {
    let orientations: [SimulatorDeviceOrientation] = [.unknown, .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight, .faceUp, .faceDown]
    for (value, orientation) in orientations.enumerated() {
      XCTAssertEqual(try SimulatorOrientationCommands.decodeMotionState("{\"orientation\":\(value)}"), orientation)
    }
  }

  func testInvalidMotionStateDoesNotDefaultToPortrait() {
    for output in ["", "{}", "null", "[]", "{\"orientation\":null}", "{\"orientation\":true}", "{\"orientation\":\"1\"}", "{\"orientation\":1.5}", "{\"orientation\":-1}", "{\"orientation\":7}"] {
      XCTAssertThrowsError(try SimulatorOrientationCommands.decodeMotionState(output), output)
    }
  }

  func testLegacyRequestUsesCurrentOrientation() throws {
    let request = try SimulatorOrientationProtocol.request()
    XCTAssertEqual(String(cString: xpc_dictionary_get_string(request, "messageType")!), "OrientationRequest")
    XCTAssertEqual(String(cString: xpc_dictionary_get_string(request, "featureIdentifier")!), SimulatorOrientationProtocol.service)
    let payload = try XCTUnwrap(xpc_dictionary_get_value(request, "payload"))
    let current = try XCTUnwrap(xpc_dictionary_get_value(payload, "currentOrientation"))
    XCTAssertTrue(xpc_get_type(current) == XPC_TYPE_DICTIONARY)
    XCTAssertEqual(xpc_dictionary_get_count(current), 0)
  }

  func testLegacyReplyPreservesAllPhysicalOrientations() throws {
    for orientation in SimulatorDeviceOrientation.allCases {
      let reply = SimulatorCoreDevice.dictionary(["currentDeviceOrientation": xpc_string_create(orientation.rawValue)])
      XCTAssertEqual(try SimulatorOrientationProtocol.orientation(reply), orientation)
    }
  }

  func testInvalidLegacyRepliesFail() {
    for reply in [xpc_null_create(), xpc_string_create("portrait"), SimulatorCoreDevice.dictionary([:])] {
      XCTAssertThrowsError(try SimulatorOrientationProtocol.orientation(reply))
    }
    for value in [xpc_null_create(), xpc_int64_create(1), xpc_bool_create(true), xpc_string_create("futureOrientation")] {
      XCTAssertThrowsError(try SimulatorOrientationProtocol.orientation(SimulatorCoreDevice.dictionary(["currentDeviceOrientation": value])))
    }
  }
}
