/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension BridgeAXWire.Envelope: CodingKey {}

/// Every accessibility answer the guest writes: `ok` beside either the verb's own fields or a failure's. The
/// verb decides `Success`, so the host decodes a response as the type of the request it sent.
@frozen public enum BridgeAXOutcome<Success: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
  case success(Success)
  case failure(BridgeAXFailure)

  public init(from decoder: Decoder) throws {
    let envelope = try decoder.container(keyedBy: BridgeAXWire.Envelope.self)
    if try envelope.decode(Bool.self, forKey: .ok) {
      self = .success(try Success(from: decoder))
    } else {
      self = .failure(try BridgeAXFailure(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var envelope = encoder.container(keyedBy: BridgeAXWire.Envelope.self)
    switch self {
    case let .success(success):
      try envelope.encode(true, forKey: .ok)
      try success.encode(to: encoder)
    case let .failure(failure):
      try envelope.encode(false, forKey: .ok)
      try failure.encode(to: encoder)
    }
  }
}

/// Why the guest could not answer. The kind decides what the host raises; the message carries the detail.
public struct BridgeAXFailure: Codable, Equatable, Sendable {
  public var message: String?
  /// Nil when the guest named no kind: a generic failure.
  public var kind: BridgeAXWire.ErrorKind?
  public var pid: Int32?
  /// The AXError of a `runtimeFailed` failure, when the runtime gave one.
  public var axError: Int32?
  /// How long an `applicationNotResponding` read waited.
  public var timeoutSeconds: Double?
  /// True on `applicationNotResponding` when the application was still working on an earlier read, so this one was
  /// refused without being sent; otherwise nil.
  public var outstanding: Bool?
  /// What a failed write did to the application.
  public var effect: BridgeAXWire.Effect?

  /// Spelled as `BridgeAXWire.Envelope` spells them.
  @frozen public enum CodingKeys: String, CodingKey, CaseIterable {
    case message = "error"
    case kind = "error_kind"
    case pid
    case axError = "ax_error"
    case timeoutSeconds = "timeout_seconds"
    case outstanding
    case effect
  }

  public init(
    message: String?, kind: BridgeAXWire.ErrorKind? = nil, pid: Int32? = nil, axError: Int32? = nil, timeoutSeconds: Double? = nil,
    outstanding: Bool? = nil, effect: BridgeAXWire.Effect? = nil
  ) {
    self.message = message
    self.kind = kind
    self.pid = pid
    self.axError = axError
    self.timeoutSeconds = timeoutSeconds
    self.outstanding = outstanding
    self.effect = effect
  }
}

// MARK: - Answers

/// The answer to a `describe`: the tree of one application, read by pid or resolved as the frontmost one.
public struct BridgeAXTreeResponse: Codable, Equatable, Sendable {
  public var tree: BridgeAXNode
  public var pid: Int32
  /// Whether the node budget ran out before the walk did.
  public var truncated: Bool
  public var automation: BridgeAXAutomationState?
  public var phases: BridgeAXGuestPhases?
  /// How the frontmost application was resolved; nil for a read by pid.
  public var method: BridgeAXFrontmostMethod?
  /// The fullscreen modal found in the tree, on a frontmost read.
  public var modal: BridgeAXModal?

  public init(
    tree: BridgeAXNode, pid: Int32, truncated: Bool, automation: BridgeAXAutomationState? = nil, phases: BridgeAXGuestPhases? = nil,
    method: BridgeAXFrontmostMethod? = nil, modal: BridgeAXModal? = nil
  ) {
    self.tree = tree
    self.pid = pid
    self.truncated = truncated
    self.automation = automation
    self.phases = phases
    self.method = method
    self.modal = modal
  }
}

/// The device's accessibility automation mode as it stood for a read, and whether the read changed it.
public struct BridgeAXAutomationState: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var asserted: Bool

  public init(enabled: Bool, asserted: Bool) {
    self.enabled = enabled
    self.asserted = asserted
  }
}

/// What the guest measured of its own work on a read.
public struct BridgeAXGuestPhases: Codable, Equatable, Sendable {
  public var traverseMilliseconds: Double?
  public var machRoundTrips: Int64?

  /// Spelled as `BridgeAXWire.Phase` spells them.
  @frozen public enum CodingKeys: String, CodingKey, CaseIterable {
    case traverseMilliseconds = "traverse_ms"
    case machRoundTrips = "mach_round_trips"
  }

  public init(traverseMilliseconds: Double?, machRoundTrips: Int64?) {
    self.traverseMilliseconds = traverseMilliseconds
    self.machRoundTrips = machRoundTrips
  }
}

/// The answer to a `hittest`: the element at the point and the application that owns it, or nothing there.
@frozen public enum BridgeAXHitTestResponse: Codable, Equatable, Sendable {
  case element(BridgeAXNode, pid: Int32)
  case empty

  public init(from decoder: Decoder) throws {
    let envelope = try decoder.container(keyedBy: BridgeAXWire.Envelope.self)
    if try envelope.decodeIfPresent(Bool.self, forKey: .empty) == true {
      self = .empty
    } else {
      self = .element(try envelope.decode(BridgeAXNode.self, forKey: .tree), pid: try envelope.decode(Int32.self, forKey: .pid))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var envelope = encoder.container(keyedBy: BridgeAXWire.Envelope.self)
    switch self {
    case let .element(node, pid):
      try envelope.encode(node, forKey: .tree)
      try envelope.encode(pid, forKey: .pid)
    case .empty:
      try envelope.encode(true, forKey: .empty)
    }
  }
}

/// The answer to a `perform` or `setvalue` that went ahead: the application written to, or nothing at the point.
@frozen public enum BridgeAXWriteResponse: Codable, Equatable, Sendable {
  case written(pid: Int32)
  case empty

  public init(from decoder: Decoder) throws {
    let envelope = try decoder.container(keyedBy: BridgeAXWire.Envelope.self)
    if try envelope.decodeIfPresent(Bool.self, forKey: .empty) == true {
      self = .empty
    } else {
      self = .written(pid: try envelope.decode(Int32.self, forKey: .pid))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var envelope = encoder.container(keyedBy: BridgeAXWire.Envelope.self)
    switch self {
    case let .written(pid): try envelope.encode(pid, forKey: .pid)
    case .empty: try envelope.encode(true, forKey: .empty)
    }
  }
}

/// The answer to a `settings-get` or `settings-set`: the setting's state afterwards.
public struct BridgeAXSettingResponse: Codable, Equatable, Sendable {
  public var enabled: Bool

  public init(enabled: Bool) {
    self.enabled = enabled
  }
}

// MARK: - Streams

/// One frame of a `settings-observe` stream: the observed setting's state, and the state of every other setting
/// the stream reports beside it.
public struct BridgeAXSettingSnapshot: Codable, Equatable, Sendable {
  private enum CodingKeys {
    static let event = BridgeAXWireKey(BridgeAXWire.Settings.Key.event)
    static let setting = BridgeAXWireKey(BridgeAXWire.Request.setting)
    static let enabled = BridgeAXWireKey(BridgeAXWire.Envelope.enabled)
    static let settings = BridgeAXWireKey(BridgeAXWire.Settings.Key.settings)
  }

  public var setting: String
  /// Nil when the frame's value is not a boolean: a setting newer than this revision may carry anything, and its
  /// snapshot must not fail the stream it arrives on.
  public var enabled: Bool?
  public var otherSettings: [String: BridgeAXOutcome<BridgeAXSettingResponse>]

  public init(setting: String, enabled: Bool?, otherSettings: [String: BridgeAXOutcome<BridgeAXSettingResponse>] = [:]) {
    self.setting = setting
    self.enabled = enabled
    self.otherSettings = otherSettings
  }

  public init(from decoder: Decoder) throws {
    let snapshot = try decoder.container(keyedBy: BridgeAXWireKey.self)
    _ = try snapshot.decode(BridgeAXWire.Settings.Event.self, forKey: CodingKeys.event)
    setting = try snapshot.decode(String.self, forKey: CodingKeys.setting)
    enabled = (try? snapshot.decodeIfPresent(Bool.self, forKey: CodingKeys.enabled)) ?? nil
    otherSettings = try snapshot.decodeIfPresent([String: BridgeAXOutcome<BridgeAXSettingResponse>].self, forKey: CodingKeys.settings) ?? [:]
  }

  public func encode(to encoder: Encoder) throws {
    var snapshot = encoder.container(keyedBy: BridgeAXWireKey.self)
    try snapshot.encode(BridgeAXWire.Settings.Event.snapshot, forKey: CodingKeys.event)
    try snapshot.encode(setting, forKey: CodingKeys.setting)
    try snapshot.encodeIfPresent(enabled, forKey: CodingKeys.enabled)
    if !otherSettings.isEmpty {
      try snapshot.encode(otherSettings, forKey: CodingKeys.settings)
    }
  }
}

/// One frame of a `quiet` stream.
@frozen public enum BridgeAXQuiescenceEvent: Codable, Equatable, Sendable {
  public typealias State = BridgeAXWire.Quiescence.State
  public typealias Signal = BridgeAXWire.Quiescence.Signal

  /// The application's state, written first once it is known and then on every change. `busySignals` names the
  /// signals holding a `busy` state and is empty otherwise.
  case state(State, busySignals: [Signal], pid: Int32)
  case touchesCompleted(pid: Int32)
  case targetChanged(pid: Int32)
  case targetExited(pid: Int32)

  private enum CodingKeys {
    static let event = BridgeAXWireKey(BridgeAXWire.Quiescence.Key.event)
    static let state = BridgeAXWireKey(BridgeAXWire.Quiescence.Key.state)
    static let signals = BridgeAXWireKey(BridgeAXWire.Quiescence.Key.signals)
    static let pid = BridgeAXWireKey(BridgeAXWire.Envelope.pid)
  }

  public init(from decoder: Decoder) throws {
    let event = try decoder.container(keyedBy: BridgeAXWireKey.self)
    let pid = try event.decode(Int32.self, forKey: CodingKeys.pid)
    switch try event.decode(BridgeAXWire.Quiescence.Event.self, forKey: CodingKeys.event) {
    case .state:
      self = .state(
        try event.decode(State.self, forKey: CodingKeys.state), busySignals: try event.decodeIfPresent([Signal].self, forKey: CodingKeys.signals) ?? [], pid: pid)
    case .touchesCompleted: self = .touchesCompleted(pid: pid)
    case .targetChanged: self = .targetChanged(pid: pid)
    case .targetExited: self = .targetExited(pid: pid)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var event = encoder.container(keyedBy: BridgeAXWireKey.self)
    switch self {
    case let .state(state, signals, pid):
      try event.encode(BridgeAXWire.Quiescence.Event.state, forKey: CodingKeys.event)
      try event.encode(state, forKey: CodingKeys.state)
      if state == .busy {
        try event.encode(signals.sorted { $0.rawValue < $1.rawValue }, forKey: CodingKeys.signals)
      }
      try event.encode(pid, forKey: CodingKeys.pid)
    case let .touchesCompleted(pid):
      try event.encode(BridgeAXWire.Quiescence.Event.touchesCompleted, forKey: CodingKeys.event)
      try event.encode(pid, forKey: CodingKeys.pid)
    case let .targetChanged(pid):
      try event.encode(BridgeAXWire.Quiescence.Event.targetChanged, forKey: CodingKeys.event)
      try event.encode(pid, forKey: CodingKeys.pid)
    case let .targetExited(pid):
      try event.encode(BridgeAXWire.Quiescence.Event.targetExited, forKey: CodingKeys.event)
      try event.encode(pid, forKey: CodingKeys.pid)
    }
  }
}

/// A coding key spelled by one of the `BridgeAXWire` vocabularies, for a frame whose keys come from several.
struct BridgeAXWireKey: CodingKey {
  let stringValue: String

  init<Vocabulary: RawRepresentable>(_ key: Vocabulary) where Vocabulary.RawValue == String {
    stringValue = key.rawValue
  }

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  var intValue: Int? { nil }

  init?(intValue: Int) {
    nil
  }
}
