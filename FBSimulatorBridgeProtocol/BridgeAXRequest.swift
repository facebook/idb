/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// How a read traverses the application, which determines the attributes elements carry.
/// `viewHierarchy` returns the app's view tree (deep, every container); `semantic` returns what an
/// accessibility client sees (flat, labelled); `singleFetch` returns the same tree as `viewHierarchy`,
/// fetched once per drawing process rather than once per node. The strategies read different child
/// relations, so neither's element count is a baseline for the other, and a reachability verdict covers
/// only what the strategy returned, not everything on screen.
public enum BridgeAXTraversal: String, Sendable, CaseIterable {
  case viewHierarchy = "view-hierarchy"
  case semantic = "semantic"
  /// One fetch for the application plus one per subtree another process draws (a web view, picker or
  /// autofill sheet), which a single fetch cannot cross into.
  case singleFetch = "single-fetch"
}

/// Selects how an in-guest frontmost read resolves the foreground application.
public enum BridgeAXFrontmostMethod: String, Sendable, CaseIterable {
  case centerPoint = "center-point"
  case windowServer = "window-server"
  case runningBoard = "runningboard"
}

public struct BridgeAXWriteAssertion: Sendable, Equatable {
  public let key: BridgeAXWire.Node
  public let value: String

  public init(key: BridgeAXWire.Node, value: String) {
    self.key = key
    self.value = value
  }
}

public struct BridgeAXWriteRequest: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case perform(BridgeAXWire.Action)
    case setValue(String)
  }

  public let kind: Kind
  public let x: Double
  public let y: Double
  public let pid: Int32?
  public let assertion: BridgeAXWriteAssertion?
  public var displayID: UInt32?

  public init(kind: Kind, x: Double, y: Double, pid: Int32?, assertion: BridgeAXWriteAssertion?, displayID: UInt32? = nil) {
    self.kind = kind
    self.x = x
    self.y = y
    self.pid = pid
    self.assertion = assertion
    self.displayID = displayID
  }

  /// Whether sending this write twice leaves the same state as sending it once.
  public var isIdempotent: Bool {
    switch kind {
    case .perform: false
    case .setValue: true
    }
  }

  public var verb: BridgeAXWire.Verb {
    switch kind {
    case .perform: .perform
    case .setValue: .setValue
    }
  }

  public var payload: [String: Any] {
    var payload: [String: Any] = [
      BridgeAXWire.Request.verb.key: verb.rawValue,
      BridgeAXWire.Request.x.key: x,
      BridgeAXWire.Request.y.key: y,
    ]
    if let pid {
      payload[BridgeAXWire.Request.pid.key] = Int(pid)
    }
    if let displayID {
      payload[BridgeAXWire.Request.displayID.key] = displayID
    }
    switch kind {
    case let .perform(action):
      payload[BridgeAXWire.Request.action.key] = action.rawValue
    case let .setValue(value):
      payload[BridgeAXWire.Request.value.key] = value
    }
    if let assertion {
      payload[BridgeAXWire.Request.assertKey.key] = assertion.key.rawValue
      payload[BridgeAXWire.Request.assertValue.key] = assertion.value
    }
    return payload
  }
}

public struct BridgeAXReadOptions: Sendable, Equatable {
  public let maxDepth: Int
  public let maxNodes: Int
  public let attributes: [String]?
  public let explainUnreachable: Bool
  public let traversal: BridgeAXTraversal
  public let automationMode: Bool?

  public init(maxDepth: Int, maxNodes: Int, attributes: [String]?, explainUnreachable: Bool, traversal: BridgeAXTraversal, automationMode: Bool?) {
    self.maxDepth = maxDepth
    self.maxNodes = maxNodes
    self.attributes = attributes
    self.explainUnreachable = explainUnreachable
    self.traversal = traversal
    self.automationMode = automationMode
  }

  public func appendingPayload(to payload: [String: Any]) -> [String: Any] {
    var payload = payload
    payload[BridgeAXWire.Request.maxDepth.key] = maxDepth
    payload[BridgeAXWire.Request.maxNodes.key] = maxNodes
    if let attributes, !attributes.isEmpty {
      payload[BridgeAXWire.Request.attributes.key] = attributes
    }
    if explainUnreachable {
      payload[BridgeAXWire.Request.explainUnreachable.key] = true
    }
    if traversal == .semantic {
      payload[BridgeAXWire.Request.translatorVocabulary.key] = true
    }
    if traversal == .singleFetch {
      payload[BridgeAXWire.Request.snapshotTree.key] = true
    }
    if let automationMode {
      payload[BridgeAXWire.Request.automationMode.key] = automationMode
    }
    return payload
  }
}

public enum BridgeAXRequest: Sendable {
  case read(pid: Int32, options: BridgeAXReadOptions, displayID: UInt32? = nil)
  case readFrontmost(x: Double, y: Double, method: BridgeAXFrontmostMethod, options: BridgeAXReadOptions, displayID: UInt32? = nil)
  case hitTest(x: Double, y: Double, attributes: [String]?, displayID: UInt32? = nil)
  case write(BridgeAXWriteRequest)
  case deviceSettingRead(String)
  case deviceSettingWrite(String, enabled: Bool)
  /// Streamed: follows the frontmost application on `displayID` when `pid` is nil. A nil tunable takes the guest's default.
  case quiescence(pid: Int32?, busyThresholdMs: Int?, quietWindowMs: Int?, displayID: UInt32? = nil)
  case displays

  public var command: BridgeCommand {
    get throws { .accessibility(try payload.mapValues(BridgeJSONValue.init(foundationValue:))) }
  }

  public var mayRetry: Bool { (try? command.mayRetry) ?? false }

  public var arguments: [String] {
    get throws { try BridgeRequest(command: command).arguments }
  }

  public var payload: [String: Any] {
    switch self {
    case let .read(pid, options, displayID):
      var payload: [String: Any] = [
        BridgeAXWire.Request.verb.key: BridgeAXWire.Verb.describe.rawValue,
        BridgeAXWire.Request.pid.key: Int(pid),
      ]
      if let displayID { payload[BridgeAXWire.Request.displayID.key] = displayID }
      return options.appendingPayload(to: payload)
    case let .readFrontmost(x, y, method, options, displayID):
      var payload: [String: Any] = [
        BridgeAXWire.Request.verb.key: BridgeAXWire.Verb.describe.rawValue,
        BridgeAXWire.Request.x.key: x,
        BridgeAXWire.Request.y.key: y,
        BridgeAXWire.Request.method.key: method.rawValue,
      ]
      if let displayID {
        payload[BridgeAXWire.Request.displayID.key] = displayID
      }
      return options.appendingPayload(to: payload)
    case let .hitTest(x, y, attributes, displayID):
      var payload: [String: Any] = [
        BridgeAXWire.Request.verb.key: BridgeAXWire.Verb.hitTest.rawValue,
        BridgeAXWire.Request.x.key: x,
        BridgeAXWire.Request.y.key: y,
      ]
      if let displayID {
        payload[BridgeAXWire.Request.displayID.key] = displayID
      }
      if let attributes, !attributes.isEmpty {
        payload[BridgeAXWire.Request.attributes.key] = attributes
      }
      return payload
    case let .write(request):
      return request.payload
    case let .deviceSettingRead(setting):
      return [
        BridgeAXWire.Request.verb.key: BridgeAXWire.Verb.settingsGet.rawValue,
        BridgeAXWire.Request.setting.key: setting,
      ]
    case let .deviceSettingWrite(setting, enabled):
      return [
        BridgeAXWire.Request.verb.key: BridgeAXWire.Verb.settingsSet.rawValue,
        BridgeAXWire.Request.setting.key: setting,
        BridgeAXWire.Request.enabled.key: enabled,
      ]
    case let .quiescence(pid, busyThresholdMs, quietWindowMs, displayID):
      var payload: [String: Any] = [BridgeAXWire.Request.verb.key: BridgeAXWire.Verb.quiet.rawValue]
      payload[BridgeAXWire.Request.pid.key] = pid.map { Int($0) }
      payload[BridgeAXWire.Request.busyThresholdMs.key] = busyThresholdMs
      payload[BridgeAXWire.Request.quietWindowMs.key] = quietWindowMs
      payload[BridgeAXWire.Request.displayID.key] = displayID
      return payload
    case .displays:
      return [BridgeAXWire.Request.verb.key: BridgeAXWire.Verb.displays.rawValue]
    }
  }
}
