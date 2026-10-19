/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension BridgeAXWire.Node: CodingKey {}

/// One element of a tree the guest read, keyed on the wire by `BridgeAXWire.Node`. Every attribute is optional:
/// a read carries only what it fetched, and an attribute the accessibility server could not answer arrives as
/// null, which decodes the same as absent.
public struct BridgeAXNode: Codable, Equatable, Sendable {
  public var elementType: BridgeAXScalar?
  public var elementBaseType: BridgeAXScalar?
  public var label: BridgeAXScalar?
  public var value: BridgeAXScalar?
  public var identifier: BridgeAXScalar?
  public var frame: BridgeAXRect?
  public var automationType: BridgeAXScalar?
  /// The `UIAccessibilityTraits` bitmask as XCTest's vocabulary answers it.
  public var xcTraits: UInt64?
  /// Nil when the read did not carry the key; a leaf the guest read carries an empty list.
  public var children: [BridgeAXNode]?
  public var windowDisplayID: UInt32?
  public var isVisible: Bool?
  /// `(-1, -1)` when the accessibility server believes no touch reaches the element, carried as it came.
  public var visiblePoint: BridgeAXPoint?
  public var centerPoint: BridgeAXPoint?
  public var userInteractionEnabled: Bool?
  public var isEnabled: Bool?
  public var translatorRole: Int?
  public var translatorSubrole: Int?
  /// The `UIAccessibilityTraits` bitmask as the translator answers it.
  public var traits: UInt64?
  public var elementIdentity: UInt64?
  /// The attributes that failed to read, mapped to why.
  public var attributeReadFailures: [String: String]?

  // A struct cannot hold an optional of itself; the indirection is kept out of the public shape.
  private indirect enum Explanation: Equatable, Sendable {
    case node(BridgeAXNode)
  }

  private var explanation: Explanation?

  /// What a display-wide hit-test at this unreachable element's centre found.
  public var explainedBy: BridgeAXNode? {
    get {
      guard case let .node(node) = explanation else { return nil }
      return node
    }
    set { explanation = newValue.map(Explanation.node) }
  }

  public init() {}

  public init(from decoder: Decoder) throws {
    let node = try decoder.container(keyedBy: BridgeAXWire.Node.self)
    elementType = try node.decodeIfPresent(BridgeAXScalar.self, forKey: .elementType)
    elementBaseType = try node.decodeIfPresent(BridgeAXScalar.self, forKey: .elementBaseType)
    label = try node.decodeIfPresent(BridgeAXScalar.self, forKey: .label)
    value = try node.decodeIfPresent(BridgeAXScalar.self, forKey: .value)
    identifier = try node.decodeIfPresent(BridgeAXScalar.self, forKey: .identifier)
    frame = try node.decodeIfPresent(BridgeAXRect.self, forKey: .frame)
    automationType = try node.decodeIfPresent(BridgeAXScalar.self, forKey: .automationType)
    xcTraits = try node.decodeIfPresent(UInt64.self, forKey: .xcTraits)
    children = try node.decodeIfPresent([BridgeAXNode].self, forKey: .children)
    windowDisplayID = try node.decodeIfPresent(UInt32.self, forKey: .windowDisplayID)
    isVisible = try node.decodeFlagIfPresent(forKey: .isVisible)
    visiblePoint = try node.decodeIfPresent(BridgeAXPoint.self, forKey: .visiblePoint)
    centerPoint = try node.decodeIfPresent(BridgeAXPoint.self, forKey: .centerPoint)
    userInteractionEnabled = try node.decodeFlagIfPresent(forKey: .userInteractionEnabled)
    explainedBy = try node.decodeIfPresent(BridgeAXNode.self, forKey: .explainedBy)
    isEnabled = try node.decodeFlagIfPresent(forKey: .isEnabled)
    translatorRole = try node.decodeIfPresent(Int.self, forKey: .translatorRole)
    translatorSubrole = try node.decodeIfPresent(Int.self, forKey: .translatorSubrole)
    traits = try node.decodeIfPresent(UInt64.self, forKey: .traits)
    elementIdentity = try node.decodeIfPresent(UInt64.self, forKey: .elementIdentity)
    attributeReadFailures = try node.decodeIfPresent([String: String].self, forKey: .attributeReadFailures)
  }

  public func encode(to encoder: Encoder) throws {
    var node = encoder.container(keyedBy: BridgeAXWire.Node.self)
    try node.encodeIfPresent(elementType, forKey: .elementType)
    try node.encodeIfPresent(elementBaseType, forKey: .elementBaseType)
    try node.encodeIfPresent(label, forKey: .label)
    try node.encodeIfPresent(value, forKey: .value)
    try node.encodeIfPresent(identifier, forKey: .identifier)
    try node.encodeIfPresent(frame, forKey: .frame)
    try node.encodeIfPresent(automationType, forKey: .automationType)
    try node.encodeIfPresent(xcTraits, forKey: .xcTraits)
    try node.encodeIfPresent(children, forKey: .children)
    try node.encodeIfPresent(windowDisplayID, forKey: .windowDisplayID)
    try node.encodeIfPresent(isVisible, forKey: .isVisible)
    try node.encodeIfPresent(visiblePoint, forKey: .visiblePoint)
    try node.encodeIfPresent(centerPoint, forKey: .centerPoint)
    try node.encodeIfPresent(userInteractionEnabled, forKey: .userInteractionEnabled)
    try node.encodeIfPresent(explainedBy, forKey: .explainedBy)
    try node.encodeIfPresent(isEnabled, forKey: .isEnabled)
    try node.encodeIfPresent(translatorRole, forKey: .translatorRole)
    try node.encodeIfPresent(translatorSubrole, forKey: .translatorSubrole)
    try node.encodeIfPresent(traits, forKey: .traits)
    try node.encodeIfPresent(elementIdentity, forKey: .elementIdentity)
    try node.encodeIfPresent(attributeReadFailures, forKey: .attributeReadFailures)
  }
}

/// An attribute whose type is whatever the accessibility server answered. The guest passes strings and numbers
/// through and describes anything else, so these four kinds are all it can carry. The element-type and automation-type
/// attributes arrive as a class name or as an `XCUIElementType` number.
@frozen public enum BridgeAXScalar: Codable, Equatable, Sendable {
  case string(String)
  case bool(Bool)
  case integer(Int64)
  case number(Double)

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    // Strings first: nearly every attribute is one, so the common case never throws.
    if let string = try? value.decode(String.self) {
      self = .string(string)
    } else if let bool = try? value.decode(Bool.self) {
      self = .bool(bool)
    } else if let integer = try? value.decode(Int64.self) {
      self = .integer(integer)
    } else {
      self = .number(try value.decode(Double.self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case let .string(string): try value.encode(string)
    case let .bool(bool): try value.encode(bool)
    case let .integer(integer): try value.encode(integer)
    case let .number(number): try value.encode(number)
    }
  }
}

/// A `CGRect` dictionary representation. JSON has no infinity or NaN, so a non-finite coordinate (routine for an
/// off-screen or still-laying-out element) travels as null and decodes as nil.
public struct BridgeAXRect: Codable, Equatable, Sendable {
  @frozen public enum CodingKeys: String, CodingKey {
    case x = "X"
    case y = "Y"
    case width = "Width"
    case height = "Height"
  }

  public var x: Double?
  public var y: Double?
  public var width: Double?
  public var height: Double?

  public init(x: Double?, y: Double?, width: Double?, height: Double?) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public init(from decoder: Decoder) throws {
    let rect = try decoder.container(keyedBy: CodingKeys.self)
    x = try rect.decodeIfPresent(Double.self, forKey: .x)
    y = try rect.decodeIfPresent(Double.self, forKey: .y)
    width = try rect.decodeIfPresent(Double.self, forKey: .width)
    height = try rect.decodeIfPresent(Double.self, forKey: .height)
  }

  /// A non-finite coordinate is written as null rather than left out, so every rect has all four keys.
  public func encode(to encoder: Encoder) throws {
    var rect = encoder.container(keyedBy: CodingKeys.self)
    try rect.encodeFinite(x, forKey: .x)
    try rect.encodeFinite(y, forKey: .y)
    try rect.encodeFinite(width, forKey: .width)
    try rect.encodeFinite(height, forKey: .height)
  }
}

/// A `CGPoint` dictionary representation, with non-finite coordinates as `BridgeAXRect` carries them.
public struct BridgeAXPoint: Codable, Equatable, Sendable {
  @frozen public enum CodingKeys: String, CodingKey {
    case x = "X"
    case y = "Y"
  }

  public var x: Double?
  public var y: Double?

  public init(x: Double?, y: Double?) {
    self.x = x
    self.y = y
  }

  public init(from decoder: Decoder) throws {
    let point = try decoder.container(keyedBy: CodingKeys.self)
    x = try point.decodeIfPresent(Double.self, forKey: .x)
    y = try point.decodeIfPresent(Double.self, forKey: .y)
  }

  public func encode(to encoder: Encoder) throws {
    var point = encoder.container(keyedBy: CodingKeys.self)
    try point.encodeFinite(x, forKey: .x)
    try point.encodeFinite(y, forKey: .y)
  }
}

extension KeyedDecodingContainer {
  /// A boolean the accessibility server may answer as `true`/`false` or as `1`/`0`.
  func decodeFlagIfPresent(forKey key: Key) throws -> Bool? {
    guard contains(key), try !decodeNil(forKey: key) else { return nil }
    if let flag = try? decode(Bool.self, forKey: key) {
      return flag
    }
    return try decode(Int64.self, forKey: key) != 0
  }
}

extension KeyedEncodingContainer {
  fileprivate mutating func encodeFinite(_ value: Double?, forKey key: Key) throws {
    guard let value, value.isFinite else {
      try encodeNil(forKey: key)
      return
    }
    try encode(value, forKey: key)
  }
}
