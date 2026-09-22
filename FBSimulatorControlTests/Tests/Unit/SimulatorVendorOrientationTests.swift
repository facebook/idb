/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import IOKit
import XCTest
import XPC

final class SimulatorVendorOrientationTests: XCTestCase {
  func testOrientationReportPreservesNamedDirections() throws {
    let cases: [(SimulatorHIDDeviceOrientation, String)] = [
      (.portrait, "portrait"), (.portraitUpsideDown, "pud"),
      (.landscapeLeft, "landscape-left"), (.landscapeRight, "landscape-right"),
    ]
    for (orientation, expected) in cases {
      let event = try orientation.vendorEvent()
      XCTAssertEqual(event.usagePage, 0xff61)
      XCTAssertEqual(event.usage, 0x5b)
      XCTAssertEqual(event.version, 0)
      let decoded = try event.data.withUnsafeBytes { bytes in
        try XCTUnwrap(
          IOCFUnserializeWithSize(
            bytes.baseAddress!.assumingMemoryBound(to: CChar.self), bytes.count, nil, 0, nil) as? [String: String])
      }
      XCTAssertEqual(
        decoded,
        [
          "provider": "com.apple.Virtualization.VirtualMachines",
          "source": "orientation-picker-control", "type": "enum", "value": expected,
        ])
    }
  }

  func testMotionCapabilityIsIndependentOfHinge() throws {
    for hinge in [false, true] {
      for motion in [false, true] {
        let reply = SimulatorCoreDevice.dictionary([
          "CoreDevice.output": SimulatorCoreDevice.dictionary([
            "hingeAngle": xpc_bool_create(hinge), "deviceMotionState": xpc_bool_create(motion),
          ])
        ])
        if motion {
          try SimulatorMotionCapability.deviceMotionState.requireSupported(in: reply)
        } else {
          XCTAssertThrowsError(try SimulatorMotionCapability.deviceMotionState.requireSupported(in: reply)) { error in
            guard case SimulatorCoreDeviceError.unsupported = error else { return XCTFail("Expected unsupported, got \(error)") }
          }
        }
      }
    }
  }

  func testUnadvertisedMotionCapabilitySelectsLegacyTransport() {
    let reply = SimulatorCoreDevice.dictionary([
      "CoreDevice.output": SimulatorCoreDevice.dictionary(["hingeAngle": xpc_bool_create(false)])
    ])
    XCTAssertThrowsError(try SimulatorMotionCapability.deviceMotionState.requireSupported(in: reply)) { error in
      guard case SimulatorCoreDeviceError.unsupported = error else { return XCTFail("Expected unsupported, got \(error)") }
    }
  }

  func testMalformedMotionCapabilityDoesNotSelectLegacyTransport() {
    for value in [xpc_int64_create(1), xpc_string_create("true"), xpc_null_create()] {
      let output = SimulatorCoreDevice.dictionary(["hingeAngle": xpc_bool_create(true)])
      xpc_dictionary_set_value(output, "deviceMotionState", value)
      let reply = SimulatorCoreDevice.dictionary(["CoreDevice.output": output])
      XCTAssertThrowsError(try SimulatorMotionCapability.deviceMotionState.requireSupported(in: reply)) { error in
        guard case SimulatorCoreDeviceError.unavailable = error else { return XCTFail("Expected invalid reply, got \(error)") }
      }
    }
  }
}
