/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreFoundation
import Foundation

public enum BridgeJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case integer(Int64)
  case unsignedInteger(UInt64)
  case number(Double)
  case string(String)
  case array([BridgeJSONValue])
  case object([String: BridgeJSONValue])

  private enum Number: Equatable {
    case signed(Int64)
    case unsigned(UInt64)
    case fractional(Double)
  }

  private var numberValue: Number? {
    switch self {
    case let .integer(value): return .signed(value)
    case let .unsignedInteger(value):
      if let signed = Int64(exactly: value) { return .signed(signed) }
      return .unsigned(value)
    case let .number(value):
      if let signed = Int64(exactly: value) { return .signed(signed) }
      if let unsigned = UInt64(exactly: value) { return .unsigned(unsigned) }
      return .fractional(value)
    case .null, .bool, .string, .array, .object: return nil
    }
  }

  /// JSON has one numeric type; integral representations compare without converting integers to Double.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    if let left = lhs.numberValue, let right = rhs.numberValue { return left == right }
    switch lhs {
    case .null:
      if case .null = rhs { return true }
    case let .bool(left):
      if case let .bool(right) = rhs { return left == right }
    case let .string(left):
      if case let .string(right) = rhs { return left == right }
    case let .array(left):
      if case let .array(right) = rhs { return left == right }
    case let .object(left):
      if case let .object(right) = rhs { return left == right }
    case .integer, .unsignedInteger, .number: break
    }
    return false
  }

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() { self = .null } else if let bool = try? value.decode(Bool.self) { self = .bool(bool) } else if let integer = try? value.decode(Int64.self) { self = .integer(integer) } else if let integer = try? value.decode(UInt64.self) { self = .unsignedInteger(integer) } else if let number = try? value.decode(Double.self) { self = .number(number) } else if let string = try? value.decode(String.self) { self = .string(string) } else if let array = try? value.decode([BridgeJSONValue].self) { self = .array(array) } else { self = .object(try value.decode([String: BridgeJSONValue].self)) }
  }

  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .null: try value.encodeNil()
    case let .bool(bool): try value.encode(bool)
    case let .integer(integer): try value.encode(integer)
    case let .unsignedInteger(integer): try value.encode(integer)
    case let .number(number): try value.encode(number)
    case let .string(string): try value.encode(string)
    case let .array(array): try value.encode(array)
    case let .object(object): try value.encode(object)
    }
  }

  public init(foundationValue value: Any) throws {
    switch value {
    case is NSNull: self = .null
    case let value as NSNumber:
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        self = .bool(value.boolValue)
      } else if let integer = Int64(value.stringValue) {
        self = .integer(integer)
      } else if let integer = UInt64(value.stringValue) {
        self = .unsignedInteger(integer)
      } else {
        guard value.doubleValue.isFinite else { throw BridgeProtocolError.invalidJSONValue }
        self = .number(value.doubleValue)
      }
    case let value as String: self = .string(value)
    case let value as [Any]: self = .array(try value.map(Self.init(foundationValue:)))
    case let value as [String: Any]: self = .object(try value.mapValues(Self.init(foundationValue:)))
    default: throw BridgeProtocolError.invalidJSONValue
    }
  }

  public var foundationValue: Any {
    switch self {
    case .null: NSNull()
    case let .bool(value): NSNumber(value: value)
    case let .integer(value): NSNumber(value: value)
    case let .unsignedInteger(value): NSNumber(value: value)
    case let .number(value): NSNumber(value: value)
    case let .string(value): value
    case let .array(values): values.map(\.foundationValue)
    case let .object(values): values.mapValues(\.foundationValue)
    }
  }
}
