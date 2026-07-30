/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A `Sendable` JSON value. Models exactly what the accessibility serializer emits — string, bool,
/// integer, double, array, object, and an explicit null — so a serialized payload can cross
/// concurrency domains (e.g. the remote-automation actor) without an `@unchecked Sendable` escape
/// hatch.
///
/// `null` is a first-class case, not a dropped key: a nil field serializes to `null` with its key
/// retained, which a deserializing consumer distinguishes from a missing key (e.g. JavaScript `null`
/// vs `undefined`). `bool`/`int`/`double` are kept distinct so the re-serialized bytes match the
/// original Foundation payload exactly.
public enum FBJSONValue: Sendable, Equatable {
  case string(String)
  case bool(Bool)
  case int(Int64)
  case double(Double)
  case array([FBJSONValue])
  case object([String: FBJSONValue])
  case null

  /// Builds a value from a dynamically-typed Foundation/bridged `Any` — the accessibility element's
  /// `axValue()`, which may be a string, a number, or nil. `nil`/`NSNull` become `.null`; an
  /// `NSNumber` is classified as bool/int/double so the re-serialized bytes match; an unrecognised
  /// object falls back to its `String(describing:)` form. The serializer's other attributes have
  /// statically-known types and build their `FBJSONValue` case directly, without this classifier.
  public init(foundation object: Any?) {
    guard let object, !(object is NSNull) else {
      self = .null
      return
    }
    switch object {
    case let value as String:
      self = .string(value)
    case let value as NSNumber:
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        self = .bool(value.boolValue)
      } else {
        let objCType = String(cString: value.objCType)
        self = (objCType == "f" || objCType == "d") ? .double(value.doubleValue) : .int(value.int64Value)
      }
    case let value as [Any]:
      self = .array(value.map { FBJSONValue(foundation: $0) })
    case let value as [String: Any]:
      self = .object(value.mapValues { FBJSONValue(foundation: $0) })
    default:
      self = .string(String(describing: object))
    }
  }

  /// The value as a JSON-serialisable Foundation object (`String`/`NSNumber`/`NSNull`/`NSArray`/
  /// `NSDictionary`), suitable for `JSONSerialization`. `null` becomes `NSNull` so the key is emitted
  /// with a JSON `null` value rather than dropped. A non-finite `double` (infinity/NaN — which JSON
  /// cannot represent) also becomes `NSNull`, since it would otherwise make `JSONSerialization` throw.
  public func toFoundationObject() -> Any {
    switch self {
    case let .string(value):
      return value
    case let .bool(value):
      return value
    case let .int(value):
      return value
    case let .double(value):
      // JSON has no representation for infinity or NaN; a non-finite value makes JSONSerialization
      // throw an uncaught NSException, so surface it as JSON null.
      guard value.isFinite else { return NSNull() }
      return value
    case let .array(value):
      return value.map { $0.toFoundationObject() }
    case let .object(value):
      return value.mapValues { $0.toFoundationObject() }
    case .null:
      return NSNull()
    }
  }
}
