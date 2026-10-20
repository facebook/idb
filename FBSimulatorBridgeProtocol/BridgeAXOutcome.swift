/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation


/// An answer that either succeeded with `Success` or failed, as a stream reports each setting beside the one it
/// observes.
@frozen public enum BridgeAXOutcome<Success: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
  case success(Success)
  case failure(BridgeAXFailure)

  private enum SuccessCodingKeys: String, CodingKey { case _0 = "value" }
  private enum FailureCodingKeys: String, CodingKey { case _0 = "reason" }
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

  private enum ElementCodingKeys: String, CodingKey { case _0 = "tree", pid }
}

/// The answer to a `perform` or `setvalue` that went ahead: the application written to, or nothing at the point.
@frozen public enum BridgeAXWriteResponse: Codable, Equatable, Sendable {
  case written(pid: Int32)
  case empty
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
  public var setting: String
  /// Nil when the setting's value is not a boolean.
  public var enabled: Bool?
  public var otherSettings: [String: BridgeAXOutcome<BridgeAXSettingResponse>]

  public init(setting: String, enabled: Bool?, otherSettings: [String: BridgeAXOutcome<BridgeAXSettingResponse>] = [:]) {
    self.setting = setting
    self.enabled = enabled
    self.otherSettings = otherSettings
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

  private enum StateCodingKeys: String, CodingKey { case _0 = "state", busySignals, pid }
}
