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
@frozen public enum BridgeAXTraversal: String, Codable, Sendable, CaseIterable {
  case viewHierarchy = "view-hierarchy"
  case semantic = "semantic"
  /// One fetch for the application plus one per subtree another process draws (a web view, picker or
  /// autofill sheet), which a single fetch cannot cross into.
  case singleFetch = "single-fetch"
}

/// Selects how an in-guest frontmost read resolves the foreground application.
@frozen public enum BridgeAXFrontmostMethod: String, Codable, Sendable, CaseIterable {
  case centerPoint = "center-point"
  case windowServer = "window-server"
  case runningBoard = "runningboard"
}

public struct BridgeAXWriteAssertion: Codable, Sendable, Equatable {
  public let key: BridgeAXWire.Node
  public let value: String

  public init(key: BridgeAXWire.Node, value: String) {
    self.key = key
    self.value = value
  }
}

public struct BridgeAXWriteRequest: Codable, Sendable, Equatable {
  @frozen public enum Kind: Codable, Sendable, Equatable {
    case perform(BridgeAXWire.Action)
    case setValue(String)

    private enum PerformCodingKeys: String, CodingKey { case _0 = "action" }
    private enum SetValueCodingKeys: String, CodingKey { case _0 = "value" }
  }

  public let kind: Kind
  public let x: Double
  public let y: Double
  public let pid: Int32?
  public let assertion: BridgeAXWriteAssertion?
  public var displayID: UInt32?
  /// Attributes the guest fetches for the hit element beyond its default list, so an assertion can name one.
  public let attributes: [String]?

  public init(kind: Kind, x: Double, y: Double, pid: Int32?, assertion: BridgeAXWriteAssertion?, displayID: UInt32? = nil, attributes: [String]? = nil) {
    self.kind = kind
    self.x = x
    self.y = y
    self.pid = pid
    self.assertion = assertion
    self.displayID = displayID
    self.attributes = attributes
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
}

public struct BridgeAXReadOptions: Codable, Sendable, Equatable {
  /// The bounds a request that names none is read with.
  public static let defaultMaxDepth = 100
  public static let defaultMaxNodes = 5000

  public let maxDepth: Int
  public let maxNodes: Int
  public let attributes: [String]?
  public let explainUnreachable: Bool
  public let traversal: BridgeAXTraversal
  public let automationMode: Bool?
  public let clientType: BridgeAXClientType

  public init(
    maxDepth: Int, maxNodes: Int, attributes: [String]?, explainUnreachable: Bool, traversal: BridgeAXTraversal, automationMode: Bool?,
    clientType: BridgeAXClientType
  ) {
    self.maxDepth = maxDepth
    self.maxNodes = maxNodes
    self.attributes = attributes
    self.explainUnreachable = explainUnreachable
    self.traversal = traversal
    self.automationMode = automationMode
    self.clientType = clientType
  }
}

/// Travels as its case's name keyed to its fields: `{"read":{"pid":42,"options":{…}}}`.
@frozen public enum BridgeAXRequest: Codable, Sendable, Equatable {
  case read(pid: Int32, options: BridgeAXReadOptions, displayID: UInt32? = nil)
  case readFrontmost(x: Double, y: Double, method: BridgeAXFrontmostMethod, options: BridgeAXReadOptions, displayID: UInt32? = nil)
  /// Display-wide when `pid` is nil: the guest names the application that owns the point.
  case hitTest(x: Double, y: Double, attributes: [String]?, clientType: BridgeAXClientType, displayID: UInt32? = nil, pid: Int32? = nil)
  case write(BridgeAXWriteRequest)
  case deviceSettingRead(String)
  case deviceSettingWrite(String, enabled: Bool)
  case deviceSettingChanges(String)
  /// Streamed: follows the frontmost application on `displayID`, resolved by `method` at (`x`, `y`), when `pid` is
  /// nil. A nil tunable takes the guest's default.
  case quiescence(
    pid: Int32?, busyThresholdMs: Int?, quietWindowMs: Int?, displayID: UInt32? = nil,
    method: BridgeAXFrontmostMethod = .windowServer, x: Double = 0, y: Double = 0)
  case displays

  // Swift names an unlabelled payload `_0`; these name it for what it holds.
  private enum WriteCodingKeys: String, CodingKey { case _0 = "request" }
  private enum DeviceSettingReadCodingKeys: String, CodingKey { case _0 = "setting" }
  private enum DeviceSettingWriteCodingKeys: String, CodingKey { case _0 = "setting", enabled }
  private enum DeviceSettingChangesCodingKeys: String, CodingKey { case _0 = "setting" }

  public var command: BridgeCommand { .accessibility(self) }

  public var verb: BridgeAXWire.Verb {
    switch self {
    case .read, .readFrontmost: .describe
    case .hitTest: .hitTest
    case let .write(request): request.verb
    case .deviceSettingRead: .settingsGet
    case .deviceSettingWrite: .settingsSet
    case .deviceSettingChanges: .settingsObserve
    case .quiescence: .quiet
    case .displays: .displays
    }
  }

  /// Only reads can be replayed after a connection failure with an uncertain outcome. Asserting automation mode
  /// beside a read is idempotent, so the read stays replayable.
  public var mayRetry: Bool {
    switch self {
    case .read, .readFrontmost, .hitTest, .deviceSettingRead, .displays: true
    case .write, .deviceSettingWrite, .deviceSettingChanges, .quiescence: false
    }
  }

  public var arguments: [String] {
    get throws { try BridgeRequest(command: command).arguments }
  }
}
