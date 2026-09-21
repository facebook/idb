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

final class SimulatorHingeTests: XCTestCase {
  func testRejectsInvalidAngles() {
    for degrees in [-1, 181, Double.nan, .infinity, -.infinity] {
      XCTAssertThrowsError(try SimulatorHingeAngle(degrees: degrees))
    }
  }

  func testRejectsDevicesWithoutTheDemonstratedHinge() throws {
    try SimulatorHingeAngle.requireSupportedModel("iPhone19,4")
    for model in [nil, "iPhone18,1", "iPad16,3"] {
      XCTAssertThrowsError(try SimulatorHingeAngle.requireSupportedModel(model))
    }
  }

  func testHingeReportCarriesBinaryControlPayload() throws {
    for degrees in [0.0, 90.0, 135.5, 180.0] {
      let event = try SimulatorHingeAngle(degrees: degrees).vendorEvent()
      let message = try XPCEncoder().encode(
        DTUHIDMessage(
          messageType: "IndigoVendorDefinedEvent",
          featureIdentifier: SimulatorDTUHIDTransport.vendorDefinedServiceName,
          payload: event))
      XCTAssertEqual(
        String(cString: xpc_dictionary_get_string(message, "featureIdentifier")!),
        "com.apple.coredevice.feature.remote.hid.vendordefined")
      let payload = try XCTUnwrap(xpc_dictionary_get_dictionary(message, "payload"))
      for (key, value) in [("usagePage", UInt64(0xff61)), ("usage", 0x5b), ("version", 0)] {
        XCTAssertEqual(xpc_get_type(try XCTUnwrap(xpc_dictionary_get_value(payload, key))), XPC_TYPE_UINT64)
        XCTAssertEqual(xpc_dictionary_get_uint64(payload, key), value)
      }
      let data = try XCTUnwrap(xpc_dictionary_get_value(payload, "data"))
      XCTAssertEqual(xpc_get_type(data), XPC_TYPE_DATA)
      let bytes = try XCTUnwrap(xpc_data_get_bytes_ptr(data))
      let decoded = try XCTUnwrap(
        IOCFUnserializeWithSize(
          bytes.assumingMemoryBound(to: CChar.self), xpc_data_get_length(data), nil, 0, nil) as? [String: Any])
      XCTAssertEqual(decoded["provider"] as? String, "com.apple.Virtualization.VirtualMachines")
      XCTAssertEqual(decoded["source"] as? String, "hinge-slider-control")
      XCTAssertEqual(decoded["type"] as? String, "range")
      XCTAssertEqual(decoded["value"] as? Double, degrees)
    }
  }
}
