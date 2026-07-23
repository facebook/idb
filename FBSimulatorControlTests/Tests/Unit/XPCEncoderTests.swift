/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest
import XPC

final class XPCEncoderTests: XCTestCase {

  private enum Phase: UInt64, Encodable {
    case start = 0
    case move = 1
    case end = 2
  }

  private struct Point: Encodable {
    let x: Double
    let y: Double
  }

  private struct Sample: Encodable {
    let name: String
    let flag: Bool
    let count: UInt64
    let phase: Phase
    let point: Point
    let optional: Point?
  }

  func testEncodesScalarsNestedAndOmitsNilOptionals() throws {
    let object = try XPCEncoder().encode(
      Sample(name: "hello", flag: false, count: 7, phase: .end, point: Point(x: 0.25, y: 0.75), optional: nil))

    XCTAssertEqual(xpc_get_type(object), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(String(cString: xpc_dictionary_get_string(object, "name")!), "hello")

    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(object, "flag")!), XPC_TYPE_BOOL)
    XCTAssertFalse(xpc_dictionary_get_bool(object, "flag"))

    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(object, "count")!), XPC_TYPE_UINT64)
    XCTAssertEqual(xpc_dictionary_get_uint64(object, "count"), 7)

    // A UInt64-raw enum encodes as a uint64 — the wire type follows the model's type.
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(object, "phase")!), XPC_TYPE_UINT64)
    XCTAssertEqual(xpc_dictionary_get_uint64(object, "phase"), 2)

    // A nested Encodable becomes a nested dictionary.
    let point = xpc_dictionary_get_dictionary(object, "point")!
    XCTAssertEqual(xpc_dictionary_get_double(point, "x"), 0.25, accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(point, "y"), 0.75, accuracy: 1e-9)

    // A nil Optional omits its key.
    XCTAssertNil(xpc_dictionary_get_value(object, "optional"))
  }

  func testEncodesPresentOptional() throws {
    let object = try XPCEncoder().encode(
      Sample(name: "x", flag: true, count: 0, phase: .start, point: Point(x: 0, y: 0), optional: Point(x: 1, y: 2)))
    XCTAssertTrue(xpc_dictionary_get_bool(object, "flag"))
    let optional = xpc_dictionary_get_dictionary(object, "optional")
    XCTAssertNotNil(optional)
    XCTAssertEqual(xpc_dictionary_get_double(optional!, "x"), 1, accuracy: 1e-9)
  }

  func testEncodesDTUHIDMessageEnvelope() throws {
    let object = try XPCEncoder().encode(
      DTUHIDMessage(messageType: "TestEvent", featureIdentifier: "com.example.feature", payload: Point(x: 0.5, y: 0.5)))

    XCTAssertEqual(String(cString: xpc_dictionary_get_string(object, "messageType")!), "TestEvent")
    XCTAssertEqual(String(cString: xpc_dictionary_get_string(object, "featureIdentifier")!), "com.example.feature")
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(object, "isBarrier")!), XPC_TYPE_BOOL)
    XCTAssertFalse(xpc_dictionary_get_bool(object, "isBarrier"))

    let payload = xpc_dictionary_get_dictionary(object, "payload")!
    XCTAssertEqual(xpc_dictionary_get_double(payload, "x"), 0.5, accuracy: 1e-9)
  }
}
