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

  func testRequiresAdvertisedHingeCapability() throws {
    try SimulatorHingeCapability.requireSupported(in: capabilityReply(xpc_bool_create(true)))
    XCTAssertThrowsError(try SimulatorHingeCapability.requireSupported(in: capabilityReply(xpc_bool_create(false)))) { error in
      guard case SimulatorCoreDeviceError.unsupported = error else { return XCTFail("Expected unsupported hinge, got \(error)") }
    }
  }

  func testMalformedCapabilityDoesNotBecomeUnsupported() {
    for value in [nil, xpc_int64_create(1), xpc_string_create("true"), xpc_null_create()] {
      XCTAssertThrowsError(try SimulatorHingeCapability.requireSupported(in: capabilityReply(value))) { error in
        guard case SimulatorCoreDeviceError.unavailable = error else { return XCTFail("Expected invalid response, got \(error)") }
      }
    }
    for reply in [xpc_null_create(), SimulatorCoreDevice.dictionary([:]), SimulatorCoreDevice.dictionary(["CoreDevice.output": xpc_bool_create(true)])] {
      XCTAssertThrowsError(try SimulatorHingeCapability.requireSupported(in: reply))
    }
  }

  func testProviderErrorTakesPrecedenceOverAdvertisedCapability() {
    let reply = capabilityReply(xpc_bool_create(true))
    xpc_dictionary_set_value(
      reply, "CoreDevice.error",
      SimulatorCoreDevice.dictionary([
        "domain": xpc_string_create("MotionProvider"), "code": xpc_int64_create(42),
      ]))
    XCTAssertThrowsError(try SimulatorHingeCapability.requireSupported(in: reply)) { error in
      XCTAssertTrue(error.localizedDescription.contains("MotionProvider (42)"))
    }
    xpc_dictionary_set_string(reply, "CoreDevice.error", "invalid")
    XCTAssertThrowsError(try SimulatorHingeCapability.requireSupported(in: reply))
  }

  private func capabilityReply(_ hinge: xpc_object_t?) -> xpc_object_t {
    let output = SimulatorCoreDevice.dictionary([:])
    xpc_dictionary_set_value(output, "hingeAngle", hinge)
    return SimulatorCoreDevice.dictionary(["CoreDevice.output": output])
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
