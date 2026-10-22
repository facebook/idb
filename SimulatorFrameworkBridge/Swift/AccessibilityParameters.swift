/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreFoundation
import FBSimulatorBridgeProtocol
import Foundation

/// A request spelled as flat parameters keyed by `BridgeAXWire.Request`, as the one-shot command line's flags give
/// them. Every field is read by the same rules whatever type it arrived as: numbers in any form, flags as strings or
/// numbers, and fields a verb does not use ignored. A frame carries the request typed instead.
public enum AccessibilityParameters {
  public static func request(_ parameters: [String: Any]) throws(BridgeAXRequestError) -> BridgeAXRequest {
    let fields = Fields(parameters)
    let verbValue = fields[.verb]
    guard case let .string(name) = verbValue, let verb = BridgeAXWire.Verb(rawValue: name) else {
      throw .unsupportedVerb(verbValue)
    }
    let pid = try fields.pid()
    let displayID = try fields.displayID()
    switch verb {
    case .displays:
      return .displays
    case .settingsGet:
      return .deviceSettingRead(try fields.setting())
    case .settingsObserve:
      return .deviceSettingChanges(try fields.setting())
    case .settingsSet:
      let setting = try fields.setting()
      guard let enabled = fields.number(.enabled)?.boolValue else { throw .missingEnabled }
      return .deviceSettingWrite(setting, enabled: enabled)
    case .hitTest:
      guard let (x, y) = fields.point() else { throw .missingPoint(.hitTest) }
      return .hitTest(x: x, y: y, attributes: fields.attributes, clientType: try fields.clientType(), displayID: displayID, pid: pid)
    case .perform:
      let actionValue = fields[.action]
      guard case let .string(name) = actionValue, let action = BridgeAXWire.Action(rawValue: name) else {
        throw .unsupportedAction(actionValue)
      }
      return .write(try fields.write(.perform(action), verb: verb, pid: pid, displayID: displayID))
    case .setValue:
      guard case let .string(value) = fields[.value] else { throw .missingValue }
      return .write(try fields.write(.setValue(value), verb: verb, pid: pid, displayID: displayID))
    case .describe:
      let options = try fields.readOptions()
      if let pid {
        return .read(pid: pid, options: options, displayID: displayID)
      }
      guard let (x, y) = fields.point() else { throw .missingPoint(.describe) }
      return .readFrontmost(x: x, y: y, method: try fields.frontmostMethod(), options: options, displayID: displayID)
    case .quiet:
      return try fields.quiescence(pid: pid, displayID: displayID)
    }
  }

  /// The parameters a JSON object spells, or nil when it is not an object.
  public static func request(json: Data) throws(BridgeAXRequestError) -> BridgeAXRequest {
    guard let parameters = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { throw .unsupportedVerb(nil) }
    return try request(parameters)
  }
}

/// The parameters, each read once as whichever JSON type it holds.
private struct Fields {
  private let parameters: [String: Any]

  init(_ parameters: [String: Any]) {
    self.parameters = parameters
  }

  subscript(_ key: BridgeAXWire.Request) -> BridgeAXRequestError.Found? {
    guard let value = parameters[key.key] else { return nil }
    switch value {
    case is NSNull: return .null
    case let string as String: return .string(string)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
      if CFNumberIsFloatType(number) { return .number(number.doubleValue) }
      return .integer(number.int64Value)
    case is [Any]: return .array
    default: return .object
    }
  }

  /// The attribute names, with non-string members dropped; an empty list is the same as none.
  var attributes: [String]? {
    guard let list = parameters[BridgeAXWire.Request.attributes.key] as? [Any] else { return nil }
    let names = list.compactMap { $0 as? String }
    return names.isEmpty ? nil : names
  }

  /// A numeric field, read as `NSNumber` so integral, fractional and boolean values convert as the guest always
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
