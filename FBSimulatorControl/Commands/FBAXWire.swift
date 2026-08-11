/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
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

    /// The node a marker's searched key reads, for the keys a write can assert on — or nil when this
    /// wire carries no such attribute.
    ///
    /// Only three of the searchable keys name something the guest fetches, because the rest are host-side
    /// derivations `FBRemoteAutomationPlatformElement` answers nil for over this wire in the first place.
    /// A marker on one of those still writes; it just goes unasserted, which is what every write over the
    /// remote backend does today.
    init?(assertableSearchKey key: FBAXSearchableKey) {
      switch key {
      case .label:
        self = .label
      case .value:
        self = .value
      case .uniqueID:
        self = .identifier
      case .title, .role, .roleDescription, .subrole, .help, .placeholder:
        return nil
      }
    }
  }

  /// Top-level keys of the guest's `{ ok, tree | error, ... }` response envelope, parsed by
  /// `FBAXTreeRead`.
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

  /// What class of thing went wrong, as the guest's `error_kind` reports it.
  ///
  /// The kind decides what the host *tells* the caller — which typed error it raises and whether any
  /// remedy applies — while the envelope's `error` carries the detail. A failure with no kind, or with
  /// one this host does not know, is a reader failure with nothing further to say about it: an unknown
  /// value must degrade to that rather than fail to parse, so a guest ahead of its host loses precision
  /// and no more.
  enum ErrorKind: String, CaseIterable {
    /// The process has no accessibility server: a dead pid, or a process that is not an application.
    case applicationUnavailable = "application_unavailable"
    /// The process has one and it did not answer in time — alive but busy, suspended or wedged.
    case applicationNotResponding = "application_not_responding"
    /// The selected frontmost strategy could not name an application.
    case frontmostUnresolved = "frontmost_unresolved"
    /// The guest could not bind the private frameworks it reads through, so no request can be served.
    case readerUnavailable = "reader_unavailable"
    /// The request was malformed — an unknown verb, or a missing or wrongly-typed argument.
    case badRequest = "bad_request"
    /// A write was refused before it was attempted: the element found at the point is not the one the
    /// caller named. Distinct from `badRequest` because the request was well-formed — the screen moved.
    case assertionFailed = "assertion_failed"
  }

  /// The guest verbs — the one-shot CLI subcommand and the persistent-transport `verb` value share this
  /// spelling.
  enum Verb: String, CaseIterable {
    case describe
    case hitTest = "hittest"
    case perform
    case setValue = "setvalue"
  }

  /// The semantic actions a `perform` can ask for.
  ///
  /// These are accessibility actions the application runs itself, not synthesized touches — the guest
  /// hands the numeric identifier to the AX runtime, and the element's own implementation decides what
  /// happens. The HID path is what simulates input; this is what asks.
  enum Action: String, CaseIterable {
    /// Activate the element — the semantic equivalent of tapping it.
    case press
    case scrollUp = "scroll-up"
    case scrollDown = "scroll-down"
    case scrollLeft = "scroll-left"
    case scrollRight = "scroll-right"
    /// Bring the element into its scroll container's viewport.
    case scrollToVisible = "scroll-to-visible"
  }
}
