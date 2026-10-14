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

@Suite
struct XPCEncoderTests {

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

  @Test
  func dataUsesNativeXPCDataAtRootAndInSingleValueContainer() throws {
    struct WrappedData: Encodable {
      let data: Data
      func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
      }
    }
    for data in [Data(), Data([0, 255, 1, 0])] {
      for encoded in [try XPCEncoder().encode(data), try XPCEncoder().encode(WrappedData(data: data))] {
        #expect(xpc_get_type(encoded) == XPC_TYPE_DATA)
        #expect(xpc_data_get_length(encoded) == data.count)
        if !data.isEmpty {
          #expect(Data(bytes: xpc_data_get_bytes_ptr(encoded)!, count: data.count) == data)
        }
      }
    }
  }

  @Test
  func encodesScalarsNestedAndOmitsNilOptionals() throws {
    let object = try XPCEncoder().encode(
      Sample(name: "hello", flag: false, count: 7, phase: .end, point: Point(x: 0.25, y: 0.75), optional: nil))

    #expect(xpc_get_type(object) == XPC_TYPE_DICTIONARY)
    #expect(String(cString: xpc_dictionary_get_string(object, "name")!) == "hello")

    #expect(xpc_get_type(xpc_dictionary_get_value(object, "flag")!) == XPC_TYPE_BOOL)
    #expect(!xpc_dictionary_get_bool(object, "flag"))

    #expect(xpc_get_type(xpc_dictionary_get_value(object, "count")!) == XPC_TYPE_UINT64)
    #expect(xpc_dictionary_get_uint64(object, "count") == 7)

    // A UInt64-raw enum encodes as a uint64 — the wire type follows the model's type.
    #expect(xpc_get_type(xpc_dictionary_get_value(object, "phase")!) == XPC_TYPE_UINT64)
    #expect(xpc_dictionary_get_uint64(object, "phase") == 2)

    let point = xpc_dictionary_get_dictionary(object, "point")!
    #expect(abs(xpc_dictionary_get_double(point, "x") - 0.25) <= 1e-9)
    #expect(abs(xpc_dictionary_get_double(point, "y") - 0.75) <= 1e-9)

    #expect(xpc_dictionary_get_value(object, "optional") == nil)
  }

  @Test
  func encodesPresentOptional() throws {
    let object = try XPCEncoder().encode(
      Sample(name: "x", flag: true, count: 0, phase: .start, point: Point(x: 0, y: 0), optional: Point(x: 1, y: 2)))
    #expect(xpc_dictionary_get_bool(object, "flag"))
    let optional = xpc_dictionary_get_dictionary(object, "optional")
    #expect(optional != nil)
    #expect(abs(xpc_dictionary_get_double(optional!, "x") - 1) <= 1e-9)
  }

  @Test
  func encodesDTUHIDMessageEnvelope() throws {
    let object = try XPCEncoder().encode(
      DTUHIDMessage(messageType: "TestEvent", featureIdentifier: "com.example.feature", payload: Point(x: 0.5, y: 0.5)))

    #expect(String(cString: xpc_dictionary_get_string(object, "messageType")!) == "TestEvent")
    #expect(String(cString: xpc_dictionary_get_string(object, "featureIdentifier")!) == "com.example.feature")
    #expect(xpc_get_type(xpc_dictionary_get_value(object, "isBarrier")!) == XPC_TYPE_BOOL)
    #expect(!xpc_dictionary_get_bool(object, "isBarrier"))

    let payload = xpc_dictionary_get_dictionary(object, "payload")!
    #expect(abs(xpc_dictionary_get_double(payload, "x") - 0.5) <= 1e-9)
  }

  // MARK: - Arrays

  private struct Report: Encodable {
    let components: [UInt64]
    let points: [Point]
    let matrix: [[Double]]
    let names: [String?]
  }

  @Test
  func encodesArraysOfScalarsDictionariesAndArrays() throws {
    let object = try XPCEncoder().encode(
      Report(
        components: [651, 13, 4], points: [Point(x: 1, y: 2), Point(x: 3, y: 4)],
        matrix: [[0, 0], [2007, 2853]], names: ["a", nil, "c"]))

    let components = try #require(xpc_dictionary_get_array(object, "components"))
    #expect(xpc_array_get_count(components) == 3)
    for (index, expected) in [651, 13, 4].enumerated() {
      #expect(xpc_get_type(xpc_array_get_value(components, index)) == XPC_TYPE_UINT64)
      #expect(xpc_array_get_uint64(components, index) == UInt64(expected))
    }

    let points = try #require(xpc_dictionary_get_array(object, "points"))
    #expect(xpc_array_get_count(points) == 2)
    let second = xpc_array_get_value(points, 1)
    #expect(xpc_get_type(second) == XPC_TYPE_DICTIONARY)
    #expect(abs(xpc_dictionary_get_double(second, "y") - 4) <= 1e-9)

    let matrix = try #require(xpc_dictionary_get_array(object, "matrix"))
    let row = xpc_array_get_value(matrix, 1)
    #expect(xpc_get_type(row) == XPC_TYPE_ARRAY)
    #expect(xpc_get_type(xpc_array_get_value(row, 0)) == XPC_TYPE_DOUBLE)
    #expect(abs(xpc_array_get_double(row, 1) - 2853) <= 1e-9)

    // A nil element keeps its slot, unlike a nil keyed property which is omitted.
    let names = try #require(xpc_dictionary_get_array(object, "names"))
    #expect(xpc_array_get_count(names) == 3)
    #expect(xpc_get_type(xpc_array_get_value(names, 1)) == XPC_TYPE_NULL)
    #expect(String(cString: xpc_array_get_string(names, 2)!) == "c")
  }

  @Test
  func encodesAnArrayAtTheRoot() throws {
    let object = try XPCEncoder().encode([true, false])
    #expect(xpc_get_type(object) == XPC_TYPE_ARRAY)
    #expect(xpc_array_get_count(object) == 2)
    #expect(xpc_array_get_bool(object, 0))
    #expect(!xpc_array_get_bool(object, 1))
  }

  /// CoreDevice encodes a duration as `[int64 high, uint64 low]`, which only a hand-written unkeyed
  /// encode can express; the wire type of each element follows the Swift type it was encoded as.
  @Test
  func unkeyedContainerPreservesEachElementsWireType() throws {
    struct Interval: Encodable {
      func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(Int64(0))
        try container.encode(UInt64(100_000_000_000_000_000))
      }
    }
    let object = try XPCEncoder().encode(Interval())
    #expect(xpc_get_type(object) == XPC_TYPE_ARRAY)
    #expect(xpc_get_type(xpc_array_get_value(object, 0)) == XPC_TYPE_INT64)
    #expect(xpc_get_type(xpc_array_get_value(object, 1)) == XPC_TYPE_UINT64)
    #expect(xpc_array_get_uint64(object, 1) == 100_000_000_000_000_000)
  }

  // MARK: - UUID

  @Test
  func uuidUsesNativeXPCUUIDAtRootAndAsAValue() throws {
    struct Channel: Encodable {
      let sideChannel: UUID
    }
    let uuid = UUID()
    let root = try XPCEncoder().encode(uuid)
    #expect(xpc_get_type(root) == XPC_TYPE_UUID)
    #expect(UUID(uuid: UnsafeRawPointer(xpc_uuid_get_bytes(root)!).load(as: uuid_t.self)) == uuid)

    let keyed = try XPCEncoder().encode(Channel(sideChannel: uuid))
    let value = try #require(xpc_dictionary_get_value(keyed, "sideChannel"))
    #expect(xpc_get_type(value) == XPC_TYPE_UUID)
    #expect(UUID(uuid: UnsafeRawPointer(xpc_uuid_get_bytes(value)!).load(as: uuid_t.self)) == uuid)

    let listed = try XPCEncoder().encode([uuid])
    #expect(xpc_get_type(xpc_array_get_value(listed, 0)) == XPC_TYPE_UUID)
  }
}
