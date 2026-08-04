/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The host side of the guest⇄host accessibility wire contract, in one place. The guest
/// (`SimulatorFrameworkBridge/AccessibilityService.m`) shares no header with the host, so every raw
/// value here must byte-match the guest's own file-scope constants; that agreement is what
/// `FBAXWireContractTests` pins host-side and the `SimulatorFrameworkBridge` tests pin guest-side.
///
/// Two further wire vocabularies live with the types that own their parsed form and are referenced
/// rather than re-declared here: the frontmost-resolution request `method` values are
/// `FBAXBridgeFrontmostMethod`, and the modal kinds are `FBAccessibilityModalInfo.Kind`
/// (`system`/`app`).
enum FBAXWire {

  /// Per-node attribute keys — the exact keys `_XCTD_fetchAttributes:forElement:` accepts and echoes
  /// back in its per-element result dictionary.
  enum Node: String {
    case elementType = "XC_kAXXCAttributeElementType"
    case elementBaseType = "XC_kAXXCAttributeElementBaseType"
    case label = "XC_kAXXCAttributeLabel"
    case value = "XC_kAXXCAttributeValue"
    case identifier = "XC_kAXXCAttributeIdentifier"
    case frame = "XC_kAXXCAttributeFrame"
    case automationType = "XC_kAXXCAttributeAutomationType"
    case children = "XC_kAXXCAttributeChildren"

    /// The attribute list requested for each element during a read. Membership *and* order are part of
    /// the contract: the guest fetches and echoes back exactly this sequence.
    static let fetchList: [String] = [
      elementType, elementBaseType, label, value, identifier, frame, automationType, children,
    ].map(\.rawValue)
  }

  /// Top-level keys of the guest's `{ ok, tree | error, ... }` response envelope, parsed by
  /// `FBAXBridgeResponse`.
  enum Envelope: String {
    case ok
    case error
    case errorKind = "error_kind"
    case empty
    case truncated
    case tree
    case pid
    case modal
  }

  /// The guest read verbs — the one-shot CLI subcommand and the persistent-transport `verb` value
  /// share this spelling.
  enum Verb: String {
    case describe
    case hitTest = "hittest"
  }
}
