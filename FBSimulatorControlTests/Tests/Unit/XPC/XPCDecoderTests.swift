/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest
import XPC

private func dictionary(_ values: [String: xpc_object_t]) -> xpc_object_t {
  let result = xpc_dictionary_create(nil, nil, 0)
  for (key, value) in values { xpc_dictionary_set_value(result, key, value) }
  return result
}

private func array(_ values: [xpc_object_t]) -> xpc_object_t {
  let result = xpc_array_create(nil, 0)
  for value in values { xpc_array_append_value(result, value) }
  return result
}

final class XPCDecoderTests: XCTestCase {

  private struct Scalars: Decodable, Equatable {
    let flag: Bool
    let name: String
    let ratio: Double
    let signed: Int64
    let unsigned: UInt64
    let small: Int8
    let byte: UInt8
    let blob: Data
    let identity: UUID
  }

  private static let uuid = UUID()

  private static let scalars = dictionary([
    "flag": xpc_bool_create(true), "name": xpc_string_create("display"), "ratio": xpc_double_create(0.5),
    "signed": xpc_int64_create(-7), "unsigned": xpc_uint64_create(7), "small": xpc_int64_create(-128),
    "byte": xpc_uint64_create(255), "blob": Data([1, 2, 3]).withUnsafeBytes { xpc_data_create($0.baseAddress, $0.count) },
    "identity": withUnsafeBytes(of: uuid.uuid) { xpc_uuid_create($0.baseAddress!.assumingMemoryBound(to: UInt8.self)) },
  ])

  func testDecodesEveryScalarFromItsNativeXPCType() throws {
    XCTAssertEqual(
      try XPCDecoder().decode(Scalars.self, from: Self.scalars),
      Scalars(
        flag: true, name: "display", ratio: 0.5, signed: -7, unsigned: 7, small: -128, byte: 255,
        blob: Data([1, 2, 3]), identity: Self.uuid))
  }

  func testScalarsAreNotCoercedBetweenTypes() {
    let substitutions: [(String, xpc_object_t)] = [
      ("flag", xpc_int64_create(1)), ("flag", xpc_string_create("true")),
      ("name", xpc_int64_create(1)), ("ratio", xpc_int64_create(1)),
      ("signed", xpc_uint64_create(7)), ("unsigned", xpc_int64_create(7)),
      ("blob", xpc_string_create("")), ("identity", xpc_string_create(Self.uuid.uuidString)),
    ]
    for (key, value) in substitutions {
      let object = xpc_copy(Self.scalars)!
      xpc_dictionary_set_value(object, key, value)
      XCTAssertThrowsError(try XPCDecoder().decode(Scalars.self, from: object), key) { error in
        guard case let DecodingError.typeMismatch(_, context) = error else { return XCTFail("\(key): \(error)") }
        XCTAssertEqual(context.codingPath.map(\.stringValue), [key])
      }
    }
  }

  func testIntegersAreRangeChecked() {
    for (key, value) in [("small", xpc_int64_create(128)), ("byte", xpc_uint64_create(256))] {
      let object = xpc_copy(Self.scalars)!
      xpc_dictionary_set_value(object, key, value)
      XCTAssertThrowsError(try XPCDecoder().decode(Scalars.self, from: object), key) { error in
        guard case let DecodingError.dataCorrupted(context) = error else { return XCTFail("\(key): \(error)") }
        XCTAssertEqual(context.codingPath.map(\.stringValue), [key])
      }
    }
  }

  func testStringsMustBeValidUTF8() {
    let invalid: [CChar] = [-1, 0]
    let object = xpc_copy(Self.scalars)!
    xpc_dictionary_set_value(object, "name", invalid.withUnsafeBufferPointer { xpc_string_create($0.baseAddress!) })
    XCTAssertThrowsError(try XPCDecoder().decode(Scalars.self, from: object)) { error in
      guard case DecodingError.dataCorrupted = error else { return XCTFail("\(error)") }
    }
  }

  // MARK: - Optionals and null

  private struct Optionals: Decodable, Equatable {
    let flag: Bool?
    let any: XPCValue?
  }

  func testAnAbsentKeyDecodesAsNil() throws {
    XCTAssertEqual(try XPCDecoder().decode(Optionals.self, from: dictionary([:])), Optionals(flag: nil, any: nil))
  }

  func testAMissingRequiredKeyNamesItself() {
    XCTAssertThrowsError(try XPCDecoder().decode(Scalars.self, from: dictionary([:]))) { error in
      guard case let DecodingError.keyNotFound(key, _) = error else { return XCTFail("\(error)") }
      XCTAssertEqual(key.stringValue, "flag")
    }
  }

  func testAnXPCNullIsNotATypedValue() {
    XCTAssertThrowsError(try XPCDecoder().decode(Optionals.self, from: dictionary(["flag": xpc_null_create()]))) { error in
      guard case DecodingError.typeMismatch = error else { return XCTFail("\(error)") }
    }
  }

  func testXPCValueCapturesAnythingIncludingNull() throws {
    let object = dictionary([
      "any": dictionary([
        "n": xpc_null_create(), "s": xpc_string_create("s"), "u": xpc_uint64_create(1), "i": xpc_int64_create(-1),
        "d": xpc_double_create(1.5), "b": xpc_bool_create(false), "a": array([xpc_null_create(), xpc_uint64_create(2)]),
        "e": XPC_ERROR_CONNECTION_INVALID,
      ])
    ])
    let decoded = try XPCDecoder().decode(Optionals.self, from: object)
    XCTAssertNil(decoded.flag)
    XCTAssertEqual(
      decoded.any,
      .dictionary([
        "n": .null, "s": .string("s"), "u": .uint64(1), "i": .int64(-1), "d": .double(1.5), "b": .bool(false),
        "a": .array([.null, .uint64(2)]), "e": .other("error"),
      ]))
    XCTAssertEqual(try XPCDecoder().decode(Optionals.self, from: dictionary(["any": xpc_null_create()])).any, .null)
  }

  // MARK: - Containers

  private struct Point: Codable, Equatable {
    let x: Double
    let y: Double
  }

  private struct Report: Decodable, Equatable {
    let components: [UInt64]
    let points: [Point]
    let matrix: [[Double]]
    let names: [String?]
  }

  func testDecodesArraysOfScalarsDictionariesAndArrays() throws {
    let object = dictionary([
      "components": array([xpc_uint64_create(651), xpc_uint64_create(13)]),
      "points": array([dictionary(["x": xpc_double_create(1), "y": xpc_double_create(2)])]),
      "matrix": array([array([xpc_double_create(0), xpc_double_create(0)]), array([xpc_double_create(2007), xpc_double_create(2853)])]),
      "names": array([xpc_string_create("a"), xpc_null_create(), xpc_string_create("c")]),
    ])
    XCTAssertEqual(
      try XPCDecoder().decode(Report.self, from: object),
      Report(components: [651, 13], points: [Point(x: 1, y: 2)], matrix: [[0, 0], [2007, 2853]], names: ["a", nil, "c"]))
  }

  func testAContainerOfTheWrongShapeIsAMismatchAtItsPath() {
    let object = dictionary(["components": dictionary([:]), "points": array([]), "matrix": array([]), "names": array([])])
    XCTAssertThrowsError(try XPCDecoder().decode(Report.self, from: object)) { error in
      guard case let DecodingError.typeMismatch(_, context) = error else { return XCTFail("\(error)") }
      XCTAssertEqual(context.codingPath.map(\.stringValue), ["components"])
    }
    XCTAssertThrowsError(try XPCDecoder().decode(Report.self, from: array([])))
    XCTAssertThrowsError(try XPCDecoder().decode(Report.self, from: XPC_ERROR_CONNECTION_INVALID))
  }

  func testAnElementFailureNamesItsIndex() {
    let object = dictionary([
      "components": array([xpc_uint64_create(1), xpc_int64_create(2)]), "points": array([]), "matrix": array([]), "names": array([]),
    ])
    XCTAssertThrowsError(try XPCDecoder().decode(Report.self, from: object)) { error in
      guard case let DecodingError.typeMismatch(_, context) = error else { return XCTFail("\(error)") }
      XCTAssertEqual(context.codingPath.map(\.stringValue), ["components", "Index 1"])
    }
  }

  func testDecodesScalarsAndArraysAtTheRoot() throws {
    XCTAssertEqual(try XPCDecoder().decode(String.self, from: xpc_string_create("root")), "root")
    XCTAssertEqual(try XPCDecoder().decode([Bool].self, from: array([xpc_bool_create(true), xpc_bool_create(false)])), [true, false])
    XCTAssertEqual(try XPCDecoder().decode(UUID.self, from: withUnsafeBytes(of: Self.uuid.uuid) { xpc_uuid_create($0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }), Self.uuid)
  }

  private enum Rotation: String, Decodable {
    case upright = "rot0"
    case clockwise = "rot90"
  }

  func testDecodesRawRepresentableEnums() throws {
    XCTAssertEqual(try XPCDecoder().decode(Rotation.self, from: xpc_string_create("rot90")), .clockwise)
    XCTAssertThrowsError(try XPCDecoder().decode(Rotation.self, from: xpc_string_create("rot45")))
    XCTAssertThrowsError(try XPCDecoder().decode(Rotation.self, from: xpc_int64_create(90)))
  }

  func testHandWrittenUnkeyedDecodeReadsMixedElementTypes() throws {
    struct Interval: Decodable, Equatable {
      let high: Int64
      let low: UInt64
      init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        high = try container.decode(Int64.self)
        low = try container.decode(UInt64.self)
        XCTAssertTrue(container.isAtEnd)
      }
    }
    let decoded = try XPCDecoder().decode(Interval.self, from: array([xpc_int64_create(0), xpc_uint64_create(100_000_000_000_000_000)]))
    XCTAssertEqual(decoded.high, 0)
    XCTAssertEqual(decoded.low, 100_000_000_000_000_000)
    XCTAssertThrowsError(try XPCDecoder().decode(Interval.self, from: array([xpc_int64_create(0)]))) { error in
      guard case DecodingError.valueNotFound = error else { return XCTFail("\(error)") }
    }
  }

  // MARK: - Round trip

  private struct Envelope: Codable, Equatable {
    let action: String
    let version: [UInt64]
    let channel: UUID
    let payload: Data
    let nested: Point?
  }

  func testRoundTripsThroughXPCEncoder() throws {
    let value = Envelope(action: "a", version: [1, 2, 3], channel: Self.uuid, payload: Data([9]), nested: Point(x: 1, y: 2))
    let object = try XPCEncoder().encode(value)
    XCTAssertEqual(try XPCDecoder().decode(Envelope.self, from: object), value)
  }
}
