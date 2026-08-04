/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// A parsed accessibility read: the raw `XC_kAXXC*` attribute tree the guest returned, the pid that
/// owns it, whether the guest's walk was cut short by the depth or node bound, and any fullscreen-modal
/// descriptor the read surfaced. One value type for what both XCUI-grade backends produce from a raw
/// read, replacing the ad-hoc `(tree, truncated, pid, modal)` tuple each used to destructure.
///
/// The serialize step (`FBAXTreeSerialization.describeAllElements`) and the truncation warning happen
/// once, in the shared `describeTree`, over this value — so a `.marker` poll that reads without
/// describing does not re-run either.
///
// SAFETY: immutable after init; `tree` is a parsed JSON/DTX value graph (Foundation value types),
// never mutated after construction and read-only at the serialize site — safe to hand across the remote
// backend's actor boundary. Mirrors the `@unchecked Sendable` convention used elsewhere in this module.
// patternlint-disable-next-line unchecked-sendable
struct FBAXTreeRead: @unchecked Sendable {
  let tree: [String: Any]
  let pid: pid_t
  let truncated: Bool
  let modal: FBAccessibilityModalInfo?
}

// MARK: - Guest JSON response parsing

/// Parses the guest's `{ "ok": Bool, "tree": {...} | "error": String }` response envelope into a read.
extension FBAXTreeRead {

  /// Parses a whole-tree read for `pid`: the tree, plus whether the guest's walk was cut short by the
  /// depth or node bound (so the caller can warn the tree is incomplete). A tree read has no empty
  /// result — an app always has a root element — so an empty response is a protocol violation rather
  /// than "nothing there". `truncated` defaults to `false` when the guest omits it (an older guest, or
  /// a complete walk).
  init(wholeTreeResponse data: Data, pid: pid_t) throws {
    let response = try Self.validatedResponse(fromResponse: data, pid: pid)
    guard let tree = try Self.node(fromValidatedResponse: response, pid: pid) else {
      throw FBAXBridgeError.guestFailure("pid \(pid): empty response to a whole-tree read")
    }
    let truncated = (response[FBAXWire.Envelope.truncated.rawValue] as? Bool) ?? false
    self.init(tree: tree, pid: pid, truncated: truncated, modal: Self.modal(fromResponse: response))
  }

  /// Parses a fused frontmost read (the guest resolved the frontmost app and read its tree in one
  /// call): the tree, whether the walk was truncated, and the pid the guest resolved and read — the
  /// host does not know that pid in advance, so it rides back in the envelope and tags the serialized
  /// elements. Any `ok:false` (no element at the anchor mid-launch, or the resolved app's accessibility
  /// server not up yet) is `frontmostUnavailable`, which the read poll treats as "not up yet"; a
  /// missing tree or pid on an `ok` response is a protocol violation (`guestFailure`).
  init(frontmostResponse data: Data) throws {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("unparseable fused frontmost describe response")
    }
    guard (response[FBAXWire.Envelope.ok.rawValue] as? Bool) == true else {
      throw FBAXBridgeError.frontmostUnavailable
    }
    guard let tree = response[FBAXWire.Envelope.tree.rawValue] as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("fused frontmost describe response without a tree")
    }
    guard let pid = response[FBAXWire.Envelope.pid.rawValue] as? Int, pid > 0 else {
      throw FBAXBridgeError.guestFailure("fused frontmost describe response without a resolved pid")
    }
    let truncated = (response[FBAXWire.Envelope.truncated.rawValue] as? Bool) ?? false
    self.init(tree: tree, pid: pid_t(pid), truncated: truncated, modal: Self.modal(fromResponse: response))
  }

  /// Parses a system-wide hit-test read: the hit node and the owning pid of the element there (the host
  /// does not know it in advance — the guest resolved which app owns the point), or `nil` when the
  /// guest reports no element at the point (a valid empty result). A failure throws, so a caller can
  /// tell empty space from a broken reader. A hit is a single element, so it carries no truncation flag
  /// or modal.
  init?(hitTestResponse data: Data) throws {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("unparseable hit-test response")
    }
    guard (response[FBAXWire.Envelope.ok.rawValue] as? Bool) == true else {
      let message = (response[FBAXWire.Envelope.error.rawValue] as? String) ?? "the guest reported a failure with no message"
      throw FBAXBridgeError.guestFailure(message)
    }
    if (response[FBAXWire.Envelope.empty.rawValue] as? Bool) == true {
      return nil
    }
    guard let node = response[FBAXWire.Envelope.tree.rawValue] as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("hit-test ok response without a tree or empty flag")
    }
    guard let pid = response[FBAXWire.Envelope.pid.rawValue] as? Int, pid > 0 else {
      throw FBAXBridgeError.guestFailure("hit-test response without an owning pid")
    }
    self.init(tree: node, pid: pid_t(pid), truncated: false, modal: nil)
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
  /// dictionary of a successful response. A failed response (`{ ok: false, error }`) throws: the typed
  /// dead-pid case for `application_unavailable` (so the conformer re-raises the backend-neutral
  /// `FBUIAutomationError.applicationUnavailable`, matching the remote backend), otherwise an opaque
  /// `guestFailure` carrying the guest's own message.
  private static func validatedResponse(fromResponse data: Data, pid: pid_t) throws -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("pid \(pid): unparseable guest response")
    }
    guard (response[FBAXWire.Envelope.ok.rawValue] as? Bool) == true else {
      if (response[FBAXWire.Envelope.errorKind.rawValue] as? String) == "application_unavailable" {
        throw FBAXBridgeError.applicationUnavailable(pid: pid)
      }
      let message = (response[FBAXWire.Envelope.error.rawValue] as? String) ?? "the guest reported a failure with no message"
      throw FBAXBridgeError.guestFailure("pid \(pid): \(message)")
    }
    return response
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
