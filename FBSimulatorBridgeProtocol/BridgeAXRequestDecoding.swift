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
public enum BridgeAXRequestError: Error, Equatable, Sendable {
  /// The verb is absent, not a string, or not one the bridge serves.
  case unsupportedVerb(BridgeJSONValue?)
  case nonPositivePid(Int32)
  case invalidDisplayID
  /// The verb needs a numeric `x` and `y`, or for `describe` a pid instead.
  case missingPoint(BridgeAXWire.Verb)
  case unsupportedAction(BridgeJSONValue?)
  case missingValue
  case unpairedAssertion
  case unassertableKey(String)
  case missingSetting
  case missingEnabled
  case unsupportedFrontmostMethod(String)
  /// A flag that is neither a boolean, a number nor a string.
  case malformedFlag(BridgeAXWire.Request)
  case negativeTunable(BridgeAXWire.Request, Int)
}

/// A request travels as the JSON object `payload` builds, so a frame carries the same bytes it always has.
extension BridgeAXRequest: Codable {
  public init(from decoder: Decoder) throws {
    let parameters = try decoder.singleValueContainer().decode([String: BridgeJSONValue].self)
    do {
      try self.init(payload: parameters)
    } catch {
      throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "\(error)", underlyingError: error))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(try payload.mapValues(BridgeJSONValue.init(foundationValue:)))
  }
}

extension BridgeAXRequest {
  /// Decodes the payload `payload` produces. Fields a verb does not use are ignored, and an absent optional field
  /// takes the value a caller that omitted it gets.
  public init(payload: [String: BridgeJSONValue]) throws(BridgeAXRequestError) {
    let fields = Fields(payload)
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
    case .settingsSet:
      let setting = try fields.setting()
      guard let enabled = fields.number(.enabled)?.boolValue else { throw .missingEnabled }
      self = .deviceSettingWrite(setting, enabled: enabled)
    case .hitTest:
      guard let (x, y) = fields.point() else { throw .missingPoint(.hitTest) }
      self = .hitTest(x: x, y: y, attributes: fields.attributes(), displayID: displayID, pid: pid)
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

private struct Fields {
  let payload: [String: BridgeJSONValue]

  init(_ payload: [String: BridgeJSONValue]) {
    self.payload = payload
  }

  subscript(_ key: BridgeAXWire.Request) -> BridgeJSONValue? {
    payload[key.key]
  }

  /// A numeric field, read as `NSNumber` so integral, fractional and boolean JSON convert as the guest always
  /// converted them.
  func number(_ key: BridgeAXWire.Request) -> NSNumber? {
    switch self[key] {
    case let .bool(value): NSNumber(value: value)
    case let .integer(value): NSNumber(value: value)
    case let .unsignedInteger(value): NSNumber(value: value)
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
    case .bool, .integer, .unsignedInteger, .number: return number(key)?.boolValue ?? false
    case .null, .array, .object: throw .malformedFlag(key)
    }
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

  /// Non-string members are dropped; an empty list is the same as none.
  func attributes() -> [String]? {
    guard case let .array(values) = self[.attributes] else { return nil }
    let names = values.compactMap { value -> String? in
      guard case let .string(name) = value else { return nil }
      return name
    }
    return names.isEmpty ? nil : names
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
    let traversal: BridgeAXTraversal =
      if try flag(.snapshotTree) {
        .singleFetch
      } else if try flag(.translatorVocabulary) {
        .semantic
      } else {
        .viewHierarchy
      }
    let explainUnreachable = traversal == .viewHierarchy ? try flag(.explainUnreachable) : (try? flag(.explainUnreachable)) ?? false
    return BridgeAXReadOptions(
      maxDepth: measure(.maxDepth).map { Int($0.int32Value) } ?? BridgeAXReadOptions.defaultMaxDepth,
      maxNodes: measure(.maxNodes).map { Int($0.int32Value) } ?? BridgeAXReadOptions.defaultMaxNodes,
      attributes: attributes(),
      explainUnreachable: explainUnreachable,
      traversal: traversal,
      automationMode: number(.automationMode)?.boolValue
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
    return BridgeAXWriteRequest(kind: kind, x: x, y: y, pid: pid, assertion: assertion, displayID: displayID, attributes: attributes())
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
