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

/// The CoreDevice action envelope every one-shot and streaming request shares, and the error
/// envelope every reply parser has to recognise.
@Suite
struct SimulatorCoreDeviceEnvelopeTests {

  private func request(version: String = "651.13.4", input: some Encodable = CoreDeviceEmptyInput()) throws -> xpc_object_t {
    try CoreDeviceRequest(
      action: "com.apple.coredevice.action.example", deviceID: "0000-DEVICE", version: CoreDeviceVersion(version), input: input
    ).encoded()
  }

  @Test
  func requestCarriesEveryEnvelopeKeyWithItsWireType() throws {
    let request = try request()
    #expect(xpc_get_type(request) == XPC_TYPE_DICTIONARY)
    #expect(xpc_dictionary_get_count(request) == 6)

    let strings = [
      "CoreDevice.actionIdentifier": "com.apple.coredevice.action.example",
      "CoreDevice.deviceIdentifier": "0000-DEVICE",
    ]
    for (key, expected) in strings {
      let value = try #require(xpc_dictionary_get_value(request, key), "\(key)")
      #expect(xpc_get_type(value) == XPC_TYPE_STRING, "\(key)")
      #expect(String(cString: xpc_string_get_string_ptr(value)!) == expected, "\(key)")
    }

    let protocolVersion = try #require(xpc_dictionary_get_value(request, "CoreDevice.CoreDeviceDDIProtocolVersion"))
    #expect(xpc_get_type(protocolVersion) == XPC_TYPE_INT64)
    #expect(xpc_int64_get_value(protocolVersion) == 1)

    let input = try #require(xpc_dictionary_get_value(request, "CoreDevice.input"))
    #expect(xpc_get_type(input) == XPC_TYPE_DICTIONARY)
    #expect(xpc_dictionary_get_count(input) == 0)
  }

  @Test
  func requestEncodesTheInstalledVersionAsComponentsAndString() throws {
    let request = try request(version: "651.13.4")
    let version = try #require(xpc_dictionary_get_dictionary(request, "CoreDevice.coreDeviceVersion"))
    #expect(xpc_dictionary_get_count(version) == 3)

    let components = try #require(xpc_dictionary_get_array(version, "components"))
    #expect(xpc_array_get_count(components) == 3)
    for (index, expected) in [651, 13, 4].enumerated() {
      let component = xpc_array_get_value(components, index)
      #expect(xpc_get_type(component) == XPC_TYPE_UINT64)
      #expect(xpc_uint64_get_value(component) == UInt64(expected))
    }

    let count = try #require(xpc_dictionary_get_value(version, "originalComponentsCount"))
    #expect(xpc_get_type(count) == XPC_TYPE_INT64)
    #expect(xpc_int64_get_value(count) == 3)

    let string = try #require(xpc_dictionary_get_value(version, "stringValue"))
    #expect(xpc_get_type(string) == XPC_TYPE_STRING)
    #expect(String(cString: xpc_string_get_string_ptr(string)!) == "651.13.4")
  }

  @Test
  func requestPassesTheInputThrough() throws {
    struct Input: Encodable {
      let flag = true
    }
    let request = try request(input: Input())
    let carried = try #require(xpc_dictionary_get_value(request, "CoreDevice.input"))
    #expect(xpc_dictionary_get_bool(carried, "flag"))
  }

  @Test
  func eachRequestHasAFreshInvocationIdentifier() throws {
    var identifiers: Set<String> = []
    for _ in 0..<3 {
      let value = try #require(xpc_dictionary_get_value(try request(), "CoreDevice.invocationIdentifier"))
      #expect(xpc_get_type(value) == XPC_TYPE_STRING)
      let identifier = String(cString: xpc_string_get_string_ptr(value)!)
      #expect(UUID(uuidString: identifier) != nil, "\(identifier)")
      identifiers.insert(identifier)
    }
    #expect(identifiers.count == 3)
  }

  @Test
  func requestRejectsVersionsThatAreNotDottedIntegers() throws {
    for version in ["", "651..4", "a.b", "651.13.4-beta", "-1.2", "1.2."] {
      let error = #expect(throws: (any Error).self, "\(version)") { try request(version: version) }
      guard let error else { continue }
      guard case SimulatorCoreDeviceError.unavailable = error else {
        Issue.record("Expected an unavailable error for \(version), got \(error)")
        continue
      }
    }
  }

  // MARK: - Error envelope

  private func errorReply(domain: xpc_object_t = xpc_string_create("com.example.provider"), code: xpc_object_t = xpc_int64_create(7)) -> xpc_object_t {
    SimulatorCoreDevice.dictionary([
      "CoreDevice.error": SimulatorCoreDevice.dictionary(["domain": domain, "code": code])
    ])
  }

  @Test
  func everyReplyParserSurfacesTheProviderErrorAsUnavailable() throws {
    let reply = errorReply()
    #expect(SimulatorDisplayProtocol.report(reply) == .failed(.unavailable("com.example.provider (7)")))
    let capabilityError = try #require(#expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply) })
    if case let SimulatorCoreDeviceError.unavailable(detail) = capabilityError {
      #expect(detail == "com.example.provider (7)")
    } else {
      Issue.record("Capability: \(capabilityError)")
    }
    let streamError = try #require(#expect(throws: (any Error).self) { try CoreDeviceReply.validate(reply) })
    if case let SimulatorCoreDeviceError.unavailable(detail) = streamError {
      #expect(detail == "com.example.provider (7)")
    } else {
      Issue.record("Stream final reply: \(streamError)")
    }
  }

  @Test
  func aMalformedProviderErrorIsStillAnError() {
    let malformed = [
      errorReply(domain: xpc_int64_create(1)),
      errorReply(code: xpc_string_create("7")),
      SimulatorCoreDevice.dictionary(["CoreDevice.error": xpc_string_create("boom")]),
    ]
    for reply in malformed {
      guard case .failed = SimulatorDisplayProtocol.report(reply) else {
        Issue.record("Display report: \(reply)")
        return
      }
      #expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply) }
      #expect(throws: (any Error).self) { try CoreDeviceReply.validate(reply) }
    }
  }

  @Test
  func aRepliedErrorTakesPrecedenceOverAValidOutput() throws {
    let reply = errorReply()
    xpc_dictionary_set_value(
      reply, "CoreDevice.output",
      SimulatorCoreDevice.dictionary(["hingeAngle": xpc_bool_create(true)]))
    let error = try #require(#expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply) })
    if case SimulatorCoreDeviceError.unavailable = error {
    } else {
      Issue.record("Capability: \(error)")
    }
    #expect(throws: (any Error).self) { try CoreDeviceReply.validate(reply) }
  }

  @Test
  func aRepliedOutputThatIsNotADictionaryIsRejected() {
    for output: xpc_object_t in [xpc_null_create(), xpc_string_create("ok"), xpc_array_create(nil, 0)] {
      let reply = SimulatorCoreDevice.dictionary(["CoreDevice.output": output])
      guard case .failed = SimulatorDisplayProtocol.report(reply) else {
        Issue.record("Display report: \(reply)")
        return
      }
      #expect(throws: (any Error).self) { try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply) }
      #expect(throws: (any Error).self) { try CoreDeviceReply.validate(reply) }
    }
  }
}
