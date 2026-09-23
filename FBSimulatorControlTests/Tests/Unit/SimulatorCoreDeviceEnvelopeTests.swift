/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest
import XPC

/// The CoreDevice action envelope every one-shot and streaming request shares, and the error
/// envelope every reply parser has to recognise.
final class SimulatorCoreDeviceEnvelopeTests: XCTestCase {

  private func request(version: String = "651.13.4", input: some Encodable = CoreDeviceEmptyInput()) throws -> xpc_object_t {
    try CoreDeviceRequest(
      action: "com.apple.coredevice.action.example", deviceID: "0000-DEVICE", version: CoreDeviceVersion(version), input: input
    ).encoded()
  }

  func testRequestCarriesEveryEnvelopeKeyWithItsWireType() throws {
    let request = try request()
    XCTAssertEqual(xpc_get_type(request), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(xpc_dictionary_get_count(request), 6)

    let strings = [
      "CoreDevice.actionIdentifier": "com.apple.coredevice.action.example",
      "CoreDevice.deviceIdentifier": "0000-DEVICE",
    ]
    for (key, expected) in strings {
      let value = try XCTUnwrap(xpc_dictionary_get_value(request, key), key)
      XCTAssertEqual(xpc_get_type(value), XPC_TYPE_STRING, key)
      XCTAssertEqual(String(cString: xpc_string_get_string_ptr(value)!), expected, key)
    }

    let protocolVersion = try XCTUnwrap(xpc_dictionary_get_value(request, "CoreDevice.CoreDeviceDDIProtocolVersion"))
    XCTAssertEqual(xpc_get_type(protocolVersion), XPC_TYPE_INT64)
    XCTAssertEqual(xpc_int64_get_value(protocolVersion), 1)

    let input = try XCTUnwrap(xpc_dictionary_get_value(request, "CoreDevice.input"))
    XCTAssertEqual(xpc_get_type(input), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(xpc_dictionary_get_count(input), 0)
  }

  func testRequestEncodesTheInstalledVersionAsComponentsAndString() throws {
    let request = try request(version: "651.13.4")
    let version = try XCTUnwrap(xpc_dictionary_get_dictionary(request, "CoreDevice.coreDeviceVersion"))
    XCTAssertEqual(xpc_dictionary_get_count(version), 3)

    let components = try XCTUnwrap(xpc_dictionary_get_array(version, "components"))
    XCTAssertEqual(xpc_array_get_count(components), 3)
    for (index, expected) in [651, 13, 4].enumerated() {
      let component = xpc_array_get_value(components, index)
      XCTAssertEqual(xpc_get_type(component), XPC_TYPE_UINT64)
      XCTAssertEqual(xpc_uint64_get_value(component), UInt64(expected))
    }

    let count = try XCTUnwrap(xpc_dictionary_get_value(version, "originalComponentsCount"))
    XCTAssertEqual(xpc_get_type(count), XPC_TYPE_INT64)
    XCTAssertEqual(xpc_int64_get_value(count), 3)

    let string = try XCTUnwrap(xpc_dictionary_get_value(version, "stringValue"))
    XCTAssertEqual(xpc_get_type(string), XPC_TYPE_STRING)
    XCTAssertEqual(String(cString: xpc_string_get_string_ptr(string)!), "651.13.4")
  }

  func testRequestPassesTheInputThrough() throws {
    struct Input: Encodable {
      let flag = true
    }
    let request = try request(input: Input())
    let carried = try XCTUnwrap(xpc_dictionary_get_value(request, "CoreDevice.input"))
    XCTAssertTrue(xpc_dictionary_get_bool(carried, "flag"))
  }

  func testEachRequestHasAFreshInvocationIdentifier() throws {
    var identifiers: Set<String> = []
    for _ in 0..<3 {
      let value = try XCTUnwrap(xpc_dictionary_get_value(try request(), "CoreDevice.invocationIdentifier"))
      XCTAssertEqual(xpc_get_type(value), XPC_TYPE_STRING)
      let identifier = String(cString: xpc_string_get_string_ptr(value)!)
      XCTAssertNotNil(UUID(uuidString: identifier), identifier)
      identifiers.insert(identifier)
    }
    XCTAssertEqual(identifiers.count, 3)
  }

  func testRequestRejectsVersionsThatAreNotDottedIntegers() {
    for version in ["", "651..4", "a.b", "651.13.4-beta", "-1.2", "1.2."] {
      XCTAssertThrowsError(try request(version: version), version) { error in
        guard case SimulatorCoreDeviceError.unavailable = error else {
          return XCTFail("Expected an unavailable error for \(version), got \(error)")
        }
      }
    }
  }

  // MARK: - Error envelope

  private func errorReply(domain: xpc_object_t = xpc_string_create("com.example.provider"), code: xpc_object_t = xpc_int64_create(7)) -> xpc_object_t {
    SimulatorCoreDevice.dictionary([
      "CoreDevice.error": SimulatorCoreDevice.dictionary(["domain": domain, "code": code])
    ])
  }

  func testEveryReplyParserSurfacesTheProviderErrorAsUnavailable() throws {
    let reply = errorReply()
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(reply)) { error in
      guard case let SimulatorCoreDeviceError.unavailable(detail) = error else { return XCTFail("Display: \(error)") }
      XCTAssertEqual(detail, "com.example.provider (7)")
    }
    XCTAssertThrowsError(try SimulatorDisplayProtocol.captureDisplays(reply)) { error in
      guard case SimulatorCoreDeviceError.unavailable = error else { return XCTFail("Capture: \(error)") }
    }
    XCTAssertThrowsError(try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply)) { error in
      guard case let SimulatorCoreDeviceError.unavailable(detail) = error else { return XCTFail("Capability: \(error)") }
      XCTAssertEqual(detail, "com.example.provider (7)")
    }
    XCTAssertThrowsError(try SimulatorHingeProtocol.checkReply(reply)) { error in
      guard case let SimulatorCoreDeviceError.unavailable(detail) = error else { return XCTFail("Hinge: \(error)") }
      XCTAssertEqual(detail, "com.example.provider (7)")
    }
  }

  func testAMalformedProviderErrorIsStillAnError() {
    let malformed = [
      errorReply(domain: xpc_int64_create(1)),
      errorReply(code: xpc_string_create("7")),
      SimulatorCoreDevice.dictionary(["CoreDevice.error": xpc_string_create("boom")]),
    ]
    for reply in malformed {
      XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(reply))
      XCTAssertThrowsError(try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply))
      XCTAssertThrowsError(try SimulatorHingeProtocol.checkReply(reply))
    }
  }

  func testARepliedErrorTakesPrecedenceOverAValidOutput() throws {
    let reply = errorReply()
    xpc_dictionary_set_value(
      reply, "CoreDevice.output",
      SimulatorCoreDevice.dictionary(["hingeAngle": xpc_bool_create(true)]))
    XCTAssertThrowsError(try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply)) { error in
      guard case SimulatorCoreDeviceError.unavailable = error else { return XCTFail("Capability: \(error)") }
    }
    XCTAssertThrowsError(try SimulatorHingeProtocol.checkReply(reply))
  }

  func testARepliedOutputThatIsNotADictionaryIsRejected() {
    for output: xpc_object_t in [xpc_null_create(), xpc_string_create("ok"), xpc_array_create(nil, 0)] {
      let reply = SimulatorCoreDevice.dictionary(["CoreDevice.output": output])
      XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(reply))
      XCTAssertThrowsError(try SimulatorMotionCapability.hingeAngle.requireSupported(in: reply))
      XCTAssertThrowsError(try SimulatorHingeProtocol.checkReply(reply))
    }
  }
}
