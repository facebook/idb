/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// A parsed axbridge read: the raw `XC_kAXXC*` tree, the owning pid, whether the guest's walk was
/// truncated, and any fullscreen-modal descriptor.
///
/// The serialize step (`FBAXTreeWalk.describeAllElements`) and the truncation warning happen
/// once, in the shared `describeTree`, over this value — so a `.marker` poll that reads without
/// describing does not re-run either.
///
// SAFETY: immutable after init; `tree` is a Foundation value graph never mutated after construction.
// patternlint-disable-next-line unchecked-sendable
struct FBAXTreeRead: @unchecked Sendable {
  let tree: [String: Any]
  let pid: pid_t
  let truncated: Bool
  let modal: FBAccessibilityModalInfo?
  /// The device's accessibility automation mode as the guest saw it. Nil from a guest predating the
  /// field, which is why it is optional rather than defaulted — "an older guest did not say" and "the
  /// device was not in automation mode" are different facts and must not collapse.
  var automation: FBAccessibilityAutomationState?
  /// What the guest measured of its own work, and what the host measured around the wire.
  var timings: FBAXReadTimings?
  /// The guest's reported phases, taken off the envelope this read already parsed so the host does not
  /// parse the response a second time.
  var phases: (traverse: CFAbsoluteTime?, machRoundTrips: Int64?) = (nil, nil)
}

/// Where a guest-backed read's time went, from both sides of the boundary.
struct FBAXReadTimings: Equatable {
  /// Wall time of the whole transport call, host-side: request out, guest work, response back.
  let roundTrip: CFAbsoluteTime
  /// Decoding the guest's JSON, host-side.
  let decode: CFAbsoluteTime
  /// The guest's own walk, as it reported it.
  let traverse: CFAbsoluteTime?
  /// Round trips to the application's accessibility server, as the guest counted them.
  let machRoundTrips: Int64?
  /// Bytes the guest sent back.
  let responseBytes: Int64

  /// The round trip less the guest's walk: acquisition, bind, guest encoding and IPC, undivided.
  var residual: CFAbsoluteTime {
    max(0, roundTrip - (traverse ?? 0))
  }
}

// MARK: - Guest JSON response parsing

/// Parses the guest's `{ "ok": Bool, "tree": {...} | "error": String }` response envelope into a read.
extension FBAXTreeRead {

  init(tree: [String: Any], pid: pid_t, truncated: Bool, modal: FBAccessibilityModalInfo?) {
    self.init(tree: tree, pid: pid, truncated: truncated, modal: modal, automation: nil)
  }

  /// The guest's reported phases, or nil from a guest predating them.
  static func guestPhases(fromResponse response: [String: Any]) -> (traverse: CFAbsoluteTime?, machRoundTrips: Int64?) {
    guard let phases = response[FBAXWire.Envelope.phases.rawValue] as? [String: Any] else {
      return (nil, nil)
    }
    // Milliseconds on the wire, seconds in the model, matching every other duration here.
    let traverse = (phases[FBAXWire.Phase.traverse.rawValue] as? Double).map { $0 / 1000 }
    let roundTrips = (phases[FBAXWire.Phase.machRoundTrips.rawValue] as? NSNumber)?.int64Value
    return (traverse, roundTrips)
  }

  /// The envelope's automation object, or nil when the guest did not send one.
  static func automation(fromResponse response: [String: Any]) -> FBAccessibilityAutomationState? {
    guard let object = response[FBAXWire.Envelope.automation.rawValue] as? [String: Any],
      let enabled = object[FBAXWire.Automation.enabled.rawValue] as? Bool
    else {
      return nil
    }
    // `asserted` absent reads as false: a guest that only reports the mode has asserted nothing.
    let asserted = (object[FBAXWire.Automation.asserted.rawValue] as? Bool) ?? false
    return FBAccessibilityAutomationState(enabled: enabled, asserted: asserted)
  }

  /// An empty response is a protocol violation — an app always has a root element. `truncated`
  /// defaults to `false` when the guest omits it.
  init(wholeTreeResponse data: Data, pid: pid_t) throws {
    let response = try Self.validatedResponse(fromResponse: data, pid: pid)
    guard let tree = try Self.node(fromValidatedResponse: response, pid: pid) else {
      throw FBAXBridgeError.guestFailure("pid \(pid): empty response to a whole-tree read")
    }
    let truncated = (response[FBAXWire.Envelope.truncated.rawValue] as? Bool) ?? false
    self.init(
      tree: tree, pid: pid, truncated: truncated, modal: Self.modal(fromResponse: response),
      automation: Self.automation(fromResponse: response)
    )
    self.phases = Self.guestPhases(fromResponse: response)
  }

  /// The pid rides back in the envelope because the guest resolved it. `ok:false` is classified by the
  /// guest's failure kind, so a resolved app with no accessibility server reads the same as via `--pid`;
  /// `method` is named only when the strategy itself could not answer.
  init(frontmostResponse data: Data, method: FBAXBridgeFrontmostMethod) throws {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("unparseable fused frontmost describe response")
    }
    guard (response[FBAXWire.Envelope.ok.rawValue] as? Bool) == true else {
      throw Self.failure(fromResponse: response, pid: nil, frontmostMethod: method)
    }
    guard let tree = response[FBAXWire.Envelope.tree.rawValue] as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("fused frontmost describe response without a tree")
    }
    // `exactly:` inside the guard, so a pid too large for a `pid_t` is a response the parser rejects
    // rather than a value the conversion traps on.
    guard let reported = response[FBAXWire.Envelope.pid.rawValue] as? Int,
      let pid = pid_t(exactly: reported), pid > 0
    else {
      throw FBAXBridgeError.guestFailure("fused frontmost describe response without a resolved pid")
    }
    let truncated = (response[FBAXWire.Envelope.truncated.rawValue] as? Bool) ?? false
    self.init(
      tree: tree, pid: pid, truncated: truncated, modal: Self.modal(fromResponse: response),
      automation: Self.automation(fromResponse: response)
    )
    self.phases = Self.guestPhases(fromResponse: response)
  }

  /// `nil` when the guest reports no element at the point — a valid empty result. A failure throws,
  /// classified by the guest's kind. A hit carries no truncation flag or modal.
  init?(hitTestResponse data: Data) throws {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("unparseable hit-test response")
    }
    guard (response[FBAXWire.Envelope.ok.rawValue] as? Bool) == true else {
      throw Self.failure(fromResponse: response, pid: nil, frontmostMethod: nil)
    }
    if (response[FBAXWire.Envelope.empty.rawValue] as? Bool) == true {
      return nil
    }
    guard let node = response[FBAXWire.Envelope.tree.rawValue] as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("hit-test ok response without a tree or empty flag")
    }
    guard let reported = response[FBAXWire.Envelope.pid.rawValue] as? Int,
      let pid = pid_t(exactly: reported), pid > 0
    else {
      throw FBAXBridgeError.guestFailure("hit-test response without an owning pid")
    }
    self.init(tree: node, pid: pid, truncated: false, modal: nil)
  }

  /// Whether a `perform`/`setvalue` landed. `empty` is a value, not a failure: only the caller can say
  /// an unoccupied point is wrong.
  static func writeLanded(fromResponse data: Data) throws -> Bool {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("unparseable write response")
    }
    guard (response[FBAXWire.Envelope.ok.rawValue] as? Bool) == true else {
      throw Self.failure(fromResponse: response, pid: nil, frontmostMethod: nil)
    }
    return (response[FBAXWire.Envelope.empty.rawValue] as? Bool) != true
  }

  /// Decodes the optional `modal` descriptor the guest adds to a describe response into a typed value,
  /// or nil when no modal is present. Host-facing enrichment — never emitted in the serialized output.
  static func modal(fromResponse response: [String: Any]) -> FBAccessibilityModalInfo? {
    guard let modal = response[FBAXWire.Envelope.modal.rawValue] as? [String: Any],
      let kindRaw = modal["kind"] as? String,
      let kind = FBAccessibilityModalInfo.Kind(rawValue: kindRaw),
      let elementType = modal["elementType"] as? String
    else {
      return nil
    }
    return FBAccessibilityModalInfo(kind: kind, elementType: elementType, label: modal["label"] as? String)
  }

  /// Parses the guest JSON and validates its `ok`/error framing, returning the top-level response
  /// dictionary of a successful response. A failed response throws whatever the guest's kind says it is.
  private static func validatedResponse(fromResponse data: Data, pid: pid_t) throws -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("pid \(pid): unparseable guest response")
    }
    guard (response[FBAXWire.Envelope.ok.rawValue] as? Bool) == true else {
      throw Self.failure(fromResponse: response, pid: pid, frontmostMethod: nil)
    }
    return response
  }

  /// The typed error a failed guest response means, from the kind the guest tagged it with. An
  /// unrecognized or absent kind is a `guestFailure` carrying the guest's message, so a newer guest
  /// degrades rather than failing to parse. `pid` is the process the caller named, used when the guest
  /// did not report one; `frontmostMethod` is non-nil only for a fused frontmost read.
  private static func failure(
    fromResponse response: [String: Any],
    pid: pid_t?,
    frontmostMethod: FBAXBridgeFrontmostMethod?
  ) -> FBAXBridgeError {
    let message = (response[FBAXWire.Envelope.error.rawValue] as? String) ?? "the guest reported a failure with no message"
    // `exactly:` so a pid too large for `pid_t` is a rejected response, not a trap.
    let reportedPid = (response[FBAXWire.Envelope.pid.rawValue] as? Int).flatMap(pid_t.init(exactly:)) ?? pid
    let rawKind = response[FBAXWire.Envelope.errorKind.rawValue] as? String
    switch rawKind.flatMap(FBAXWire.ErrorKind.init(rawValue:)) {
    case .applicationUnavailable:
      return .applicationUnavailable(pid: reportedPid)
    case .applicationNotResponding:
      return .applicationNotResponding(pid: reportedPid)
    case .readerUnavailable:
      return .readerUnavailable(message)
    case .frontmostUnresolved:
      // Only a fused frontmost read asked for a strategy. The kind arriving on any other verb is a guest
      // that answered something it was not asked, so it degrades rather than inventing a method to blame.
      guard let frontmostMethod else {
        return .guestFailure(message)
      }
      return .frontmostUnresolved(method: frontmostMethod, reason: message)
    case .assertionFailed:
      // Only a write can provoke this, and the conformer re-raises it against the query it resolved —
      // the guest knows what it found under the point, but not which marker sent the write there.
      return .assertionFailed(message)
    case .badRequest, .none:
      // A malformed request is a host bug, not something a user can act on, so it stays opaque and
      // carries the guest's description of what it rejected.
      guard let pid else {
        return .guestFailure(message)
      }
      return .guestFailure("pid \(pid): \(message)")
    }
  }

  /// The node a successful response carries, or `nil` for a successful *empty* result
  /// (`{ ok: true, empty: true }`) — which only a hit-test produces.
  private static func node(fromValidatedResponse response: [String: Any], pid: pid_t) throws -> [String: Any]? {
    if (response[FBAXWire.Envelope.empty.rawValue] as? Bool) == true {
      return nil
    }
    guard let tree = response[FBAXWire.Envelope.tree.rawValue] as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("pid \(pid): ok response without a tree or empty flag")
    }
    return tree
  }
}
