/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest
import XPC

private func touchscreenValue(id: String = "display-a", serviceID: UInt64 = 0x127) -> xpc_object_t {
  SimulatorCoreDevice.dictionary([
    "displayUUID": xpc_string_create(id), "_ServiceID": xpc_uint64_create(serviceID),
    "PrimaryUsagePage": xpc_uint64_create(0x0D), "PrimaryUsage": xpc_uint64_create(0x04),
  ])
}

private func touchscreenReply(_ services: [xpc_object_t]) -> xpc_object_t {
  SimulatorCoreDevice.dictionary(["connectedServices": SimulatorCoreDevice.array(services)])
}

final class SimulatorTouchscreenReadTests: XCTestCase {
  func testRequestUsesUniversalHIDEnvelope() throws {
    let request = try SimulatorTouchscreenProtocol.request()
    XCTAssertEqual(xpc_dictionary_get_count(request), 2)
    XCTAssertTrue(xpc_get_type(try XCTUnwrap(xpc_dictionary_get_value(request, "isBarrier"))) == XPC_TYPE_BOOL)
    XCTAssertFalse(xpc_dictionary_get_bool(request, "isBarrier"))
    let payload = try XCTUnwrap(xpc_dictionary_get_value(request, "payload"))
    XCTAssertTrue(xpc_get_type(payload) == XPC_TYPE_DICTIONARY)
    XCTAssertEqual(xpc_dictionary_get_count(payload), 1)
    let connectedServices = try XCTUnwrap(xpc_dictionary_get_value(payload, "connectedServices"))
    XCTAssertTrue(xpc_get_type(connectedServices) == XPC_TYPE_DICTIONARY)
    XCTAssertEqual(xpc_dictionary_get_count(connectedServices), 0)
  }

  func testRuntimeIdentityMapsArbitraryTouchscreenTargets() throws {
    let services = [touchscreenValue(id: "display-z", serviceID: 0x1FF), touchscreenValue()]
    XCTAssertEqual(
      try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply(services)),
      [
        SimulatorTouchscreen(displayUniqueID: "display-a", digitizerTarget: 39),
        SimulatorTouchscreen(displayUniqueID: "display-z", digitizerTarget: 255),
      ])
  }

  func testOtherHIDServicesDoNotNeedDisplayIdentity() throws {
    let keyboard = SimulatorCoreDevice.dictionary([
      "_ServiceID": xpc_uint64_create(0x200),
      "PrimaryUsagePage": xpc_uint64_create(0), "PrimaryUsage": xpc_uint64_create(0),
    ])
    let trackpad = SimulatorCoreDevice.dictionary([
      "_ServiceID": xpc_uint64_create(0x501),
      "PrimaryUsagePage": xpc_uint64_create(1), "PrimaryUsage": xpc_uint64_create(2),
    ])
    XCTAssertEqual(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([keyboard, trackpad])), [])
    XCTAssertEqual(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([])), [])
  }

  func testLegacyProviderWithoutIdentitiesReportsUnsupportedCapability() {
    let legacy = touchscreenValue()
    xpc_dictionary_set_value(legacy, "displayUUID", nil)
    XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([legacy]))) { error in
      guard case SimulatorCoreDeviceError.unsupported = error else { return XCTFail("Expected unsupported identities: \(error)") }
    }
    XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([legacy, legacy]))) { error in
      guard case SimulatorCoreDeviceError.unsupported = error else { return XCTFail("Expected unsupported identities: \(error)") }
    }
    let identified = touchscreenValue(id: "display-b", serviceID: 0x128)
    XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([legacy, identified]))) { error in
      guard case SimulatorCoreDeviceError.malformed = error else { return XCTFail("Expected malformed: \(error)") }
    }
    xpc_dictionary_set_int64(legacy, "_ServiceID", 0x127)
    XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([legacy]))) { error in
      guard case SimulatorCoreDeviceError.malformed = error else { return XCTFail("Expected malformed: \(error)") }
    }
  }

  func testAmbiguousIdentityOrTargetIsRejected() {
    for duplicate in [touchscreenValue(serviceID: 0x128), touchscreenValue(id: "display-b")] {
      XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([touchscreenValue(), duplicate])))
    }
  }

  func testInvalidServiceNamespaceAndMainAliasAreRejected() {
    for serviceID: UInt64 in [0, 0xFF, 0x100, 0x200, 0x100000127, .max] {
      XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([touchscreenValue(serviceID: serviceID)])))
    }
  }

  func testMalformedIdentityAndUnsignedFieldsAreRejected() {
    for id in ["", String(repeating: "x", count: 1025)] {
      XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([touchscreenValue(id: id)])))
    }
    for key in ["displayUUID", "_ServiceID"] {
      let service = touchscreenValue()
      xpc_dictionary_set_value(service, key, nil)
      XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service])))
      xpc_dictionary_set_int64(service, key, 0x127)
      XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service])))
    }
  }

  func testServicesWithoutRecognizedTouchscreenUsageAreIgnored() throws {
    for key in ["PrimaryUsagePage", "PrimaryUsage"] {
      for value: xpc_object_t? in [nil, xpc_int64_create(4), xpc_string_create("4"), xpc_null_create()] {
        let service = touchscreenValue()
        xpc_dictionary_set_value(service, key, value)
        XCTAssertEqual(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service])), [])
        XCTAssertEqual(
          try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service, touchscreenValue()])),
          [SimulatorTouchscreen(displayUniqueID: "display-a", digitizerTarget: 39)])
      }
    }
  }

  func testInvalidUTF8IdentityIsRejected() {
    let service = touchscreenValue()
    let invalidUTF8: [CChar] = [-1, 0]
    let identity = invalidUTF8.withUnsafeBufferPointer { xpc_string_create($0.baseAddress!) }
    xpc_dictionary_set_value(service, "displayUUID", identity)
    XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service])))
  }

  func testMissingMalformedAndOversizedRepliesFail() {
    let invalid = [
      XPC_ERROR_CONNECTION_INVALID, SimulatorCoreDevice.dictionary([:]),
      SimulatorCoreDevice.dictionary(["connectedServices": xpc_bool_create(false)]),
      touchscreenReply([xpc_null_create()]),
      touchscreenReply((0..<257).map { touchscreenValue(id: "display-\($0)") }),
    ]
    for reply in invalid {
      XCTAssertThrowsError(try SimulatorTouchscreenProtocol.touchscreens(reply))
    }
  }
}
