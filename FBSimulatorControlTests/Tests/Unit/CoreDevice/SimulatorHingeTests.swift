/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import IOKit
import Testing
import XPC

@Suite
struct SimulatorHingeTests {
  @Test
  func rejectsInvalidAngles() {
    for degrees in [-1, 181, Double.nan, .infinity, -.infinity] {
      #expect(throws: (any Error).self) { try SimulatorHingeAngle(degrees: degrees) }
    }
  }

  @Test
  func requiresAdvertisedHingeCapability() throws {
    try SimulatorMotionCapability.hingeAngle.requireSupported(in: capabilityReply(xpc_bool_create(true)))
    for value in [nil, xpc_bool_create(false)] {
      let error = #expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: capabilityReply(value)) }
      guard let error else { continue }
      guard case SimulatorCoreDeviceError.unsupported = error else {
        Issue.record("Expected unsupported hinge, got \(error)")
        continue
      }
    }
  }

  /// A caller that asked for the hinge on an ordinary simulator gets told what it needs, and a
  /// caller parsing the message can still recognise the capability signal in it.
  @Test
  func unsupportedHingeNamesTheHardwareItNeeds() throws {
    let error = try #require(#expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: capabilityReply(nil)) })
    #expect(error.localizedDescription.contains("supported only on iPhone Duo simulators"))
    #expect(error.localizedDescription.contains("not supported"))
  }

  @Test
  func malformedCapabilityDoesNotBecomeUnsupported() throws {
    for value in [xpc_int64_create(1), xpc_string_create("true"), xpc_null_create()] {
      let error = #expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: capabilityReply(value)) }
      guard let error else { continue }
      guard case SimulatorCoreDeviceError.malformed = error else {
        Issue.record("Expected invalid response, got \(error)")
        continue
      }
    }
    for reply in [xpc_null_create(), SimulatorCoreDevice.dictionary([:]), SimulatorCoreDevice.dictionary(["CoreDevice.output": xpc_bool_create(true)])] {
      #expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply) }
    }
  }

  @Test
  func providerErrorTakesPrecedenceOverAdvertisedCapability() throws {
    let reply = capabilityReply(xpc_bool_create(true))
    xpc_dictionary_set_value(
      reply, "CoreDevice.error",
      SimulatorCoreDevice.dictionary([
        "domain": xpc_string_create("MotionProvider"), "code": xpc_int64_create(42),
      ]))
    let error = try #require(#expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply) })
    #expect(error.localizedDescription.contains("MotionProvider (42)"))
    xpc_dictionary_set_string(reply, "CoreDevice.error", "invalid")
    #expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply) }
  }

  private func capabilityReply(_ hinge: xpc_object_t?) -> xpc_object_t {
    let output = SimulatorCoreDevice.dictionary([:])
    xpc_dictionary_set_value(output, "hingeAngle", hinge)
    return SimulatorCoreDevice.dictionary(["CoreDevice.output": output])
  }

  @Test
  func hingeReportCarriesBinaryControlPayload() throws {
    for degrees in [0.0, 90.0, 135.5, 180.0] {
      let event = try SimulatorHingeAngle(degrees: degrees).vendorEvent()
      let message = try XPCEncoder().encode(
        DTUHIDMessage(
          messageType: "IndigoVendorDefinedEvent",
          featureIdentifier: SimulatorVendorHIDTransport.serviceName,
          payload: event))
      #expect(
        String(cString: xpc_dictionary_get_string(message, "featureIdentifier")!) == "com.apple.coredevice.feature.remote.hid.vendordefined")
      let payload = try #require(xpc_dictionary_get_dictionary(message, "payload"))
      for (key, value) in [("usagePage", UInt64(0xff61)), ("usage", 0x5b), ("version", 0)] {
        let field = try #require(xpc_dictionary_get_value(payload, key))
        #expect(xpc_get_type(field) == XPC_TYPE_UINT64)
        #expect(xpc_dictionary_get_uint64(payload, key) == value)
      }
      let data = try #require(xpc_dictionary_get_value(payload, "data"))
      #expect(xpc_get_type(data) == XPC_TYPE_DATA)
      let bytes = try #require(xpc_data_get_bytes_ptr(data))
      let decoded = try #require(
        IOCFUnserializeWithSize(
          bytes.assumingMemoryBound(to: CChar.self), xpc_data_get_length(data), nil, 0, nil) as? [String: Any])
      #expect(decoded["provider"] as? String == "com.apple.Virtualization.VirtualMachines")
      #expect(decoded["source"] as? String == "hinge-slider-control")
      #expect(decoded["type"] as? String == "range")
      #expect(decoded["value"] as? Double == degrees)
    }
  }
}
