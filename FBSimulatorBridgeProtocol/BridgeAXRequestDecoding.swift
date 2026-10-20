/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreFoundation
import Foundation

/// Why a payload does not decode to a `BridgeAXRequest`. The cases carry what the guest needs to name the problem;
/// wording it is the guest's job.
@frozen public enum BridgeAXRequestError: Error, Equatable, Sendable {
  /// What a field held when it was not what its verb needs: its JSON type, and its value when that is a scalar.
  @frozen public enum Found: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null
    case array
    case object
  }

  /// The verb is absent, not a string, or not one the bridge serves.
  case unsupportedVerb(Found?)
  case nonPositivePid(Int32)
  case invalidDisplayID
  /// The verb needs a numeric `x` and `y`, or for `describe` a pid instead.
  case missingPoint(BridgeAXWire.Verb)
  case unsupportedAction(Found?)
  case missingValue
  case unpairedAssertion
  case unassertableKey(String)
  case missingSetting
  case missingEnabled
  case unsupportedFrontmostMethod(String)
  /// The traversal is absent (nil), not a string, or not one the bridge runs.
  case unsupportedTraversal(Found?)
  /// The client type is absent (nil), not an integer, or not one the translator carries.
  case unsupportedClientType(Found?)
  /// A read named a client but a traversal that makes no translator request.
  case clientTypeNeedsSemanticTraversal(BridgeAXTraversal)
  /// A flag that is neither a boolean, a number nor a string.
  case malformedFlag(BridgeAXWire.Request)
  case negativeTunable(BridgeAXWire.Request, Int)
}

/// A request travels as a JSON object keyed by `BridgeAXWire.Request`, holding only the fields its verb uses.
extension BridgeAXRequest: Codable {
  /// Fields a verb does not use are ignored, and an absent optional field takes the value a caller that omitted it
  /// gets. A request that does not decode throws a `DecodingError` whose underlying error is the `BridgeAXRequestError`
  /// naming what is wrong.
  public init(from decoder: Decoder) throws {
    let fields = try Fields(decoder.container(keyedBy: Key.self))
    do {
      try self.init(fields)
    } catch {
      throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "\(error)", underlyingError: error))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    try container.encode(verb.rawValue, forKey: .verb)
    switch self {
    case let .read(pid, options, displayID):
      try container.encode(Int(pid), forKey: .pid)
      try container.encodeIfPresent(displayID, forKey: .displayID)
      try options.encode(into: &container)
    case let .readFrontmost(x, y, method, options, displayID):
      try container.encode(x, forKey: .x)
      try container.encode(y, forKey: .y)
      try container.encode(method.rawValue, forKey: .method)
      try container.encodeIfPresent(displayID, forKey: .displayID)
      try options.encode(into: &container)
    case let .hitTest(x, y, attributes, clientType, displayID, pid):
      try container.encode(x, forKey: .x)
      try container.encode(y, forKey: .y)
      try container.encode(clientType.rawValue, forKey: .clientType)
      try container.encodeIfPresent(pid.map { Int($0) }, forKey: .pid)
      try container.encodeIfPresent(displayID, forKey: .displayID)
      try container.encode(attributes: attributes)
    case let .write(request):
      try request.encode(into: &container)
    case let .deviceSettingRead(setting), let .deviceSettingChanges(setting):
      try container.encode(setting, forKey: .setting)
    case let .deviceSettingWrite(setting, enabled):
      try container.encode(setting, forKey: .setting)
      try container.encode(enabled, forKey: .enabled)
    case let .quiescence(pid, busyThresholdMs, quietWindowMs, displayID, method, x, y):
      try container.encodeIfPresent(pid.map { Int($0) }, forKey: .pid)
      try container.encodeIfPresent(busyThresholdMs, forKey: .busyThresholdMs)
      try container.encodeIfPresent(quietWindowMs, forKey: .quietWindowMs)
      try container.encodeIfPresent(displayID, forKey: .displayID)
      if method != .windowServer {
        try container.encode(method.rawValue, forKey: .method)
      }
      if x != 0 || y != 0 {
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
      }
    case .displays:
      break
    }
  }

  /// The request as a JSON object, for a caller that reads it field by field.
  public var payload: [String: Any] {
    guard let data = try? JSONEncoder().encode(self), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }

  private init(_ fields: Fields) throws(BridgeAXRequestError) {
    let verbValue = fields[.verb]
    guard case let .string(name) = verbValue, let verb = BridgeAXWire.Verb(rawValue: name) else {
      throw .unsupportedVerb(verbValue)
    }
    let pid = try fields.pid()
    let displayID = try fields.displayID()
    switch verb {
    case .displays:
      self = .displays
    case .settingsGet:
      self = .deviceSettingRead(try fields.setting())
    case .settingsObserve:
      self = .deviceSettingChanges(try fields.setting())
    case .settingsSet:
      let setting = try fields.setting()
      guard let enabled = fields.number(.enabled)?.boolValue else { throw .missingEnabled }
      self = .deviceSettingWrite(setting, enabled: enabled)
    case .hitTest:
      guard let (x, y) = fields.point() else { throw .missingPoint(.hitTest) }
      self = .hitTest(x: x, y: y, attributes: fields.attributes, clientType: try fields.clientType(), displayID: displayID, pid: pid)
    case .perform:
      let actionValue = fields[.action]
      guard case let .string(name) = actionValue, let action = BridgeAXWire.Action(rawValue: name) else {
        throw .unsupportedAction(actionValue)
      }
      self = .write(try fields.write(.perform(action), verb: verb, pid: pid, displayID: displayID))
    case .setValue:
      guard case let .string(value) = fields[.value] else { throw .missingValue }
      self = .write(try fields.write(.setValue(value), verb: verb, pid: pid, displayID: displayID))
    case .describe:
      let options = try fields.readOptions()
      if let pid {
        self = .read(pid: pid, options: options, displayID: displayID)
        return
      }
      guard let (x, y) = fields.point() else { throw .missingPoint(.describe) }
      self = .readFrontmost(x: x, y: y, method: try fields.frontmostMethod(), options: options, displayID: displayID)
    case .quiet:
      self = try fields.quiescence(pid: pid, displayID: displayID)
    }
  }
}

extension BridgeAXReadOptions {
  fileprivate func encode(into container: inout KeyedEncodingContainer<Key>) throws {
    try container.encode(maxDepth, forKey: .maxDepth)
    try container.encode(maxNodes, forKey: .maxNodes)
    try container.encode(attributes: attributes)
    if explainUnreachable {
      try container.encode(true, forKey: .explainUnreachable)
    }
    try container.encode(traversal.rawValue, forKey: .traversal)
    try container.encode(clientType.rawValue, forKey: .clientType)
    try container.encodeIfPresent(automationMode, forKey: .automationMode)
  }
}

extension BridgeAXWriteRequest {
  fileprivate func encode(into container: inout KeyedEncodingContainer<Key>) throws {
    try container.encode(x, forKey: .x)
    try container.encode(y, forKey: .y)
    try container.encodeIfPresent(pid.map { Int($0) }, forKey: .pid)
    try container.encodeIfPresent(displayID, forKey: .displayID)
    switch kind {
    case let .perform(action):
      try container.encode(action.rawValue, forKey: .action)
    case let .setValue(value):
      try container.encode(value, forKey: .value)
    }
    if let assertion {
      try container.encode(assertion.key.rawValue, forKey: .assertKey)
      try container.encode(assertion.value, forKey: .assertValue)
    }
    try container.encode(attributes: attributes)
  }
}

extension BridgeRequest {
  /// Why the accessibility request a frame carries does not decode, so the guest can answer it with an accessibility
  /// failure rather than failing the frame. Nil for a frame that is not an accessibility request, or whose request
  /// decodes.
  public static func accessibilityRequestError(of data: Data) -> BridgeAXRequestError? {
    do {
      _ = try JSONDecoder().decode(AccessibilityCommand.self, from: data)
      return nil
    } catch let DecodingError.dataCorrupted(context) {
      return context.underlyingError as? BridgeAXRequestError
    } catch {
      return nil
    }
  }

  private struct AccessibilityCommand: Decodable {
    struct Command: Decodable {
      struct Parameters: Decodable {
        let action: BridgeAXRequest
      }
      let accessibility: Parameters
    }
    let command: Command
  }
}

private struct Key: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }

  init(_ field: BridgeAXWire.Request) {
    stringValue = field.key
  }

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    nil
  }

  static let verb = Key(.verb)
  static let pid = Key(.pid)
  static let displayID = Key(.displayID)
  static let x = Key(.x)
  static let y = Key(.y)
  static let method = Key(.method)
  static let action = Key(.action)
  static let value = Key(.value)
  static let assertKey = Key(.assertKey)
  static let assertValue = Key(.assertValue)
  static let attributes = Key(.attributes)
  static let setting = Key(.setting)
  static let enabled = Key(.enabled)
  static let maxDepth = Key(.maxDepth)
  static let maxNodes = Key(.maxNodes)
  static let explainUnreachable = Key(.explainUnreachable)
  static let traversal = Key(.traversal)
  static let clientType = Key(.clientType)
  static let automationMode = Key(.automationMode)
  static let busyThresholdMs = Key(.busyThresholdMs)
  static let quietWindowMs = Key(.quietWindowMs)
}

extension KeyedEncodingContainer where Key == FBSimulatorBridgeProtocol.Key {
  /// An empty list is sent as none.
  fileprivate mutating func encode(attributes: [String]?) throws {
    if let attributes, !attributes.isEmpty {
      try encode(attributes, forKey: .attributes)
    }
  }
}

/// The request's fields as the frame holds them. Each is read once, as whichever JSON type it is, so every field is
/// interpreted by the one set of rules below whatever type the sender chose.
private struct Fields {
  private let found: [String: BridgeAXRequestError.Found]
  /// The attribute names, with non-string members dropped; an empty list is the same as none.
  let attributes: [String]?

  init(_ container: KeyedDecodingContainer<Key>) throws {
    var found: [String: BridgeAXRequestError.Found] = [:]
    for field in BridgeAXWire.Request.allCases {
      let key = Key(field)
      guard container.contains(key) else { continue }
      found[field.key] = Self.found(key, in: container)
    }
    self.found = found
    attributes = Self.names(in: container)
  }

  private static func found(_ key: Key, in container: KeyedDecodingContainer<Key>) -> BridgeAXRequestError.Found {
    if (try? container.decodeNil(forKey: key)) == true { return .null }
    if let value = try? container.decode(Bool.self, forKey: key) { return .bool(value) }
    if let value = try? container.decode(Int64.self, forKey: key) { return .integer(value) }
    if let value = try? container.decode(Double.self, forKey: key) { return .number(value) }
    if let value = try? container.decode(String.self, forKey: key) { return .string(value) }
    if (try? container.nestedUnkeyedContainer(forKey: key)) != nil { return .array }
    return .object
  }

  private static func names(in container: KeyedDecodingContainer<Key>) -> [String]? {
    guard var list = try? container.nestedUnkeyedContainer(forKey: .attributes) else { return nil }
    var names: [String] = []
    while !list.isAtEnd {
      if let name = try? list.decode(String.self) {
        names.append(name)
      } else if (try? list.decode(Skipped.self)) == nil {
        break
      }
    }
    return names.isEmpty ? nil : names
  }

  /// Consumes one list member of any type.
  private struct Skipped: Decodable {
    init(from decoder: Decoder) throws {}
  }

  subscript(_ key: BridgeAXWire.Request) -> BridgeAXRequestError.Found? {
    found[key.key]
  }

  /// A numeric field, read as `NSNumber` so integral, fractional and boolean JSON convert as the guest always
  /// converted them.
  func number(_ key: BridgeAXWire.Request) -> NSNumber? {
    switch self[key] {
    case let .bool(value): NSNumber(value: value)
    case let .integer(value): NSNumber(value: value)
    case let .number(value): NSNumber(value: value)
    case .null, .string, .array, .object, nil: nil
    }
  }

  /// A coordinate or count, where a boolean is not a number.
  func measure(_ key: BridgeAXWire.Request) -> NSNumber? {
    if case .bool = self[key] { return nil }
    return number(key)
  }

  /// A flag that is off unless asked for; a string reads as `NSString.boolValue` does.
  func flag(_ key: BridgeAXWire.Request) throws(BridgeAXRequestError) -> Bool {
    switch self[key] {
    case nil: return false
    case let .string(value): return (value as NSString).boolValue
    case .bool, .integer, .number: return number(key)?.boolValue ?? false
    case .null, .array, .object: throw .malformedFlag(key)
    }
  }

  func traversal() throws(BridgeAXRequestError) -> BridgeAXTraversal {
    let value = self[.traversal]
    guard case let .string(name) = value, let traversal = BridgeAXTraversal(rawValue: name) else {
      throw .unsupportedTraversal(value)
    }
    return traversal
  }

  func clientType() throws(BridgeAXRequestError) -> BridgeAXClientType {
    let value = self[.clientType]
    guard case let .integer(integer) = value, let raw = UInt64(exactly: integer), let clientType = BridgeAXClientType(rawValue: raw) else {
      throw .unsupportedClientType(value)
    }
    return clientType
  }

  func string(_ key: BridgeAXWire.Request) -> String? {
    guard case let .string(value) = self[key] else { return nil }
    return value
  }

  func pid() throws(BridgeAXRequestError) -> Int32? {
    guard let pid = measure(.pid)?.int32Value else { return nil }
    guard pid > 0 else { throw .nonPositivePid(pid) }
    return pid
  }

  func displayID() throws(BridgeAXRequestError) -> UInt32? {
    guard self[.displayID] != nil else { return nil }
    guard let number = measure(.displayID), let displayID = UInt32(exactly: number.doubleValue), displayID > 0 else {
      throw .invalidDisplayID
    }
    return displayID
  }

  func point() -> (Double, Double)? {
    guard let x = measure(.x)?.doubleValue, let y = measure(.y)?.doubleValue else { return nil }
    return (x, y)
  }

  func setting() throws(BridgeAXRequestError) -> String {
    guard let setting = string(.setting) else { throw .missingSetting }
    return setting
  }

  func frontmostMethod() throws(BridgeAXRequestError) -> BridgeAXFrontmostMethod {
    guard let name = string(.method) else { return .windowServer }
    guard let method = BridgeAXFrontmostMethod(rawValue: name) else { throw .unsupportedFrontmostMethod(name) }
    return method
  }

  /// A flag the selected traversal does not use is not read, so a malformed one does not fail the read.
  func readOptions() throws(BridgeAXRequestError) -> BridgeAXReadOptions {
    let traversal = try traversal()
    let clientType = try clientType()
    if clientType != .noClient, traversal != .semantic {
      throw .clientTypeNeedsSemanticTraversal(traversal)
    }
    let explainUnreachable = traversal == .viewHierarchy ? try flag(.explainUnreachable) : (try? flag(.explainUnreachable)) ?? false
    return BridgeAXReadOptions(
      maxDepth: measure(.maxDepth).map { Int($0.int32Value) } ?? BridgeAXReadOptions.defaultMaxDepth,
      maxNodes: measure(.maxNodes).map { Int($0.int32Value) } ?? BridgeAXReadOptions.defaultMaxNodes,
      attributes: attributes,
      explainUnreachable: explainUnreachable,
      traversal: traversal,
      automationMode: number(.automationMode)?.boolValue,
      clientType: clientType
    )
  }

  func write(_ kind: BridgeAXWriteRequest.Kind, verb: BridgeAXWire.Verb, pid: Int32?, displayID: UInt32?) throws(BridgeAXRequestError) -> BridgeAXWriteRequest {
    guard let (x, y) = point() else { throw .missingPoint(verb) }
    let assertion: BridgeAXWriteAssertion?
    switch (string(.assertKey), string(.assertValue)) {
    case (nil, nil):
      assertion = nil
    case let (key?, value?):
      guard let node = BridgeAXWire.Node(rawValue: key) else { throw .unassertableKey(key) }
      assertion = BridgeAXWriteAssertion(key: node, value: value)
    default:
      throw .unpairedAssertion
    }
    return BridgeAXWriteRequest(kind: kind, x: x, y: y, pid: pid, assertion: assertion, displayID: displayID, attributes: attributes)
  }

  func quiescence(pid: Int32?, displayID: UInt32?) throws(BridgeAXRequestError) -> BridgeAXRequest {
    var tunables: [Int?] = []
    for key in [BridgeAXWire.Request.busyThresholdMs, .quietWindowMs] {
      let value = measure(key)?.intValue
      if let value, value < 0 { throw .negativeTunable(key, value) }
      tunables.append(value)
    }
    let (x, y) = point() ?? (0, 0)
    return .quiescence(
      pid: pid, busyThresholdMs: tunables[0], quietWindowMs: tunables[1], displayID: displayID,
      method: try frontmostMethod(), x: x, y: y)
  }
}
