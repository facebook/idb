/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

/**
 Encodes any `Encodable` value into an `xpc_object_t`, mirroring how `JSONEncoder` produces `Data`.

 Keyed containers become XPC dictionaries (nested for nested `Encodable` values). Scalars map to the
 matching XPC scalar: `UInt`/`UInt8…UInt64` → `uint64`, `Int`/`Int8…Int64` → `int64`, `Double`/`Float`
 → `double`, `Bool` → `bool`, `String` → `string`. Optional properties that are `nil` are omitted (no
 key is written), so a model's optionals decide which keys appear on the wire. Unkeyed (array)
 containers are unsupported — no Indigo event needs them.

 This lets each wire message be expressed as a plain `Encodable` Swift model whose property types
 carry the wire types (e.g. a `UInt64` field can only encode to an `xpc_uint64`), instead of
 hand-rolling `xpc_dictionary_set_*` calls.
 */
struct XPCEncoder {
  func encode<Value: Encodable>(_ value: Value) throws -> xpc_object_t {
    let encoder = XPCEncoderImpl()
    try value.encode(to: encoder)
    guard let object = encoder.storage.object else {
      throw EncodingError.invalidValue(
        value, EncodingError.Context(codingPath: [], debugDescription: "Value did not encode any XPC object"))
    }
    return object
  }
}

/// Shared, mutable result slot — a reference so the value-type containers can write the built object.
private final class XPCBox {
  var object: xpc_object_t?
}

private struct XPCEncoderImpl: Encoder {
  let storage: XPCBox
  var codingPath: [CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  init(storage: XPCBox = XPCBox(), codingPath: [CodingKey] = []) {
    self.storage = storage
    self.codingPath = codingPath
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    let dictionary = storage.object ?? xpc_dictionary_create(nil, nil, 0)
    storage.object = dictionary
    return KeyedEncodingContainer(XPCKeyedContainer<Key>(dictionary: dictionary, codingPath: codingPath))
  }

  func singleValueContainer() -> SingleValueEncodingContainer {
    XPCSingleValueContainer(storage: storage, codingPath: codingPath)
  }

  func unkeyedContainer() -> UnkeyedEncodingContainer {
    fatalError("XPCEncoder does not support unkeyed (array) containers")
  }
}

private struct XPCKeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let dictionary: xpc_object_t
  var codingPath: [CodingKey]

  func encodeNil(forKey key: Key) throws {} // omit the key entirely

  func encode(_ value: Bool, forKey key: Key) throws { xpc_dictionary_set_bool(dictionary, key.stringValue, value) }
  func encode(_ value: String, forKey key: Key) throws { xpc_dictionary_set_string(dictionary, key.stringValue, value) }
  func encode(_ value: Double, forKey key: Key) throws { xpc_dictionary_set_double(dictionary, key.stringValue, value) }
  func encode(_ value: Float, forKey key: Key) throws { xpc_dictionary_set_double(dictionary, key.stringValue, Double(value)) }
  func encode(_ value: Int, forKey key: Key) throws { xpc_dictionary_set_int64(dictionary, key.stringValue, Int64(value)) }
  func encode(_ value: Int8, forKey key: Key) throws { xpc_dictionary_set_int64(dictionary, key.stringValue, Int64(value)) }
  func encode(_ value: Int16, forKey key: Key) throws { xpc_dictionary_set_int64(dictionary, key.stringValue, Int64(value)) }
  func encode(_ value: Int32, forKey key: Key) throws { xpc_dictionary_set_int64(dictionary, key.stringValue, Int64(value)) }
  func encode(_ value: Int64, forKey key: Key) throws { xpc_dictionary_set_int64(dictionary, key.stringValue, value) }
  func encode(_ value: UInt, forKey key: Key) throws { xpc_dictionary_set_uint64(dictionary, key.stringValue, UInt64(value)) }
  func encode(_ value: UInt8, forKey key: Key) throws { xpc_dictionary_set_uint64(dictionary, key.stringValue, UInt64(value)) }
  func encode(_ value: UInt16, forKey key: Key) throws { xpc_dictionary_set_uint64(dictionary, key.stringValue, UInt64(value)) }
  func encode(_ value: UInt32, forKey key: Key) throws { xpc_dictionary_set_uint64(dictionary, key.stringValue, UInt64(value)) }
  func encode(_ value: UInt64, forKey key: Key) throws { xpc_dictionary_set_uint64(dictionary, key.stringValue, value) }

  func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    let nested = XPCEncoderImpl(codingPath: codingPath + [key])
    try value.encode(to: nested)
    guard let object = nested.storage.object else {
      throw EncodingError.invalidValue(
        value, EncodingError.Context(codingPath: codingPath + [key], debugDescription: "Nested value did not encode any XPC object"))
    }
    xpc_dictionary_set_value(dictionary, key.stringValue, object)
  }

  func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type, forKey key: Key
  ) -> KeyedEncodingContainer<NestedKey> {
    let nested = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_value(dictionary, key.stringValue, nested)
    return KeyedEncodingContainer(XPCKeyedContainer<NestedKey>(dictionary: nested, codingPath: codingPath + [key]))
  }

  func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
    fatalError("XPCEncoder does not support unkeyed (array) containers")
  }

  func superEncoder() -> Encoder { XPCEncoderImpl(storage: XPCBox(), codingPath: codingPath) }
  func superEncoder(forKey key: Key) -> Encoder { XPCEncoderImpl(storage: XPCBox(), codingPath: codingPath + [key]) }
}

private struct XPCSingleValueContainer: SingleValueEncodingContainer {
  let storage: XPCBox
  var codingPath: [CodingKey]

  func encodeNil() throws {} // leaves the slot empty

  mutating func encode(_ value: Bool) throws { storage.object = xpc_bool_create(value) }
  mutating func encode(_ value: String) throws { storage.object = value.withCString { xpc_string_create($0) } }
  mutating func encode(_ value: Double) throws { storage.object = xpc_double_create(value) }
  mutating func encode(_ value: Float) throws { storage.object = xpc_double_create(Double(value)) }
  mutating func encode(_ value: Int) throws { storage.object = xpc_int64_create(Int64(value)) }
  mutating func encode(_ value: Int8) throws { storage.object = xpc_int64_create(Int64(value)) }
  mutating func encode(_ value: Int16) throws { storage.object = xpc_int64_create(Int64(value)) }
  mutating func encode(_ value: Int32) throws { storage.object = xpc_int64_create(Int64(value)) }
  mutating func encode(_ value: Int64) throws { storage.object = xpc_int64_create(value) }
  mutating func encode(_ value: UInt) throws { storage.object = xpc_uint64_create(UInt64(value)) }
  mutating func encode(_ value: UInt8) throws { storage.object = xpc_uint64_create(UInt64(value)) }
  mutating func encode(_ value: UInt16) throws { storage.object = xpc_uint64_create(UInt64(value)) }
  mutating func encode(_ value: UInt32) throws { storage.object = xpc_uint64_create(UInt64(value)) }
  mutating func encode(_ value: UInt64) throws { storage.object = xpc_uint64_create(value) }

  mutating func encode<T: Encodable>(_ value: T) throws {
    let nested = XPCEncoderImpl(storage: storage, codingPath: codingPath)
    try value.encode(to: nested)
  }
}
