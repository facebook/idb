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
    /// Whether the accessibility server believes a touch reaches this element at all. The primitive
    /// XCUITest's `isHittable` is built on — *not* "is on screen": a full-screen container that passes
    /// touches through to its children reports `false`.
    case isVisible = "XC_kAXXCAttributeIsVisible"
    /// The point the accessibility server believes a touch actually reaches, or `(-1, -1)` when it
    /// believes none does. For a partially covered element this is *not* the centre, which is the whole
    /// signal: tapping the centre lands on whatever covers it.
    case visiblePoint = "XC_kAXXCAttributeVisiblePoint"
    /// The element's own centre — what automation taps today. Read only to compare against
    /// `visiblePoint`; a divergence is what identifies a partially covered element.
    case centerPoint = "XC_kAXXCAttributeCenterPoint"
    case userInteractionEnabled = "XC_kAXXCAttributeIsUserInteractionEnabled"
    /// What a display-wide hit-test at an unreachable element's centre found, as the guest reports it.
    ///
    /// Not an `XC_kAXXC*` attribute — the accessibility server does not vend this, the in-guest reader
    /// derives it — hence the reader's own namespace. It exists so the host does not have to issue a
    /// hit-test per unreachable element of its own, which costs a round trip each; the guest is already
    /// walking the tree with the runtime bound, so it answers inline for the price of the response that
    /// was coming anyway.
    case explainedBy = "FBExplainedBy"
    /// Whether the element is enabled, as the accessibility translator answers it.
    ///
    /// The reader's own namespace because XCTest's vocabulary has no counterpart — which is precisely why
    /// a read through it reports `enabled` as an explicit null. Only a read through the translator's
    /// vocabulary carries this key, so its absence keeps every other read answering null as before.
    case isEnabled = "FBIsEnabled"
    /// The translator's `role`, as the translator's own integer.
    ///
    /// Deliberately *not* mapped onto `elementType`, which carries `XCUIElementType` names: the mapping
    /// from these integers onto those names is only partly known, and a number where consumers expect a
    /// name is worse than an absent field. Declared here because this enum is the wire vocabulary rather
    /// than the subset the host happens to read. `FBAXRoleVocabulary.name(forTranslatorRole:)` maps the
    /// identified integers; the rest ride the wire unmapped so the mapping can be extended from real
    /// screens.
    case translatorRole = "FBTranslatorRole"
    /// The translator's `subrole`, as its own integer. It refines the role rather than replacing it: a
    /// toggle is a check box with a switch subrole, a search field a text field with a search subrole.
    /// `FBAXRoleVocabulary.name(forTranslatorSubrole:)` maps the identified integers.
    case translatorSubrole = "FBTranslatorSubrole"
    /// The `UIAccessibilityTraits` bitmask, as the translator answers it. Carried raw: the trait
    /// constants live in a macOS-only header the guest cannot import, and nothing decodes it yet.
    case traits = "FBTraits"
    /// A per-element identity from the translator, stable while the element lives. The `XC_kAXXCAttribute*`
    /// namespace has no counterpart, so this is what lets two reads be compared element by element.
    case elementIdentity = "FBElementIdentity"

    /// The attribute list a read requests for each element when it names none of its own. Membership
    /// *and* order are part of the contract: the guest fetches and echoes back exactly this sequence.
    ///
    /// A read may name a different list through `Request.attributes`; this is what both sides fall back
    /// to when it does not, which is what keeps a default read byte-identical on the wire.
    static let defaultFetchList: [String] = [
      elementType, elementBaseType, label, value, identifier, frame, automationType, children,
    ].map(\.rawValue)

    /// The attributes `FBAXKeys.interactable` is derived from. Fetched only when that key is requested,
    /// which is what keeps them off the wire for every read that does not ask.
    static let interactableAttributes: [Node] = [.isVisible, .visiblePoint, .centerPoint, .userInteractionEnabled]

    /// The attribute list a read must request to serialize `keys`, or nil when the default list already
    /// carries everything needed.
    ///
    /// Nil rather than "the default list" so the caller can omit the request field entirely: an absent
    /// field is what makes a default read byte-identical to one from a host that predates it.
    static func fetchList(for keys: Set<FBAXKeys>) -> [String]? {
      guard keys.contains(.interactable) || keys.contains(.occludedBy) else {
        return nil
      }
      return defaultFetchList + interactableAttributes.map(\.rawValue)
    }

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
    case automation
    case phases
  }

  /// Keys of the envelope's `phases` object — what the guest measured of its own work. The host's own
  /// phases are not here: it measures those itself, and a duration is only trustworthy from the process
  /// that holds both ends of it.
  enum Phase: String {
    case traverse = "traverse_ms"
    case machRoundTrips = "mach_round_trips"
  }

  /// Keys of the envelope's `automation` object: the device's accessibility automation mode as it stood
  /// for the read, and whether the read changed it.
  enum Automation: String {
    case enabled
    case asserted
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
    /// Asks a persistent `serve` guest to exit. Only a `serve` process has anything to answer.
    case shutdown
  }

  /// The fields of a request, in both spellings the guest accepts them in.
  ///
  /// One case per field rather than two vocabularies, because the persistent transport sends JSON and the
  /// one-shot transport sends argv for the *same* request — declaring the pair together is what stops the
  /// two drifting into requests that mean different things depending on which transport is holding them.
  ///
  /// These were the last of the wire spelled as bare literals at each call site. The node keys, verbs,
  /// actions and failure kinds were all pinned; a field name was not, so a typo in `maxNodes` reached the
  /// guest as a field it does not read, and the read silently fell back to the guest's own budget instead
  /// of the caller's.
  enum Request: String, CaseIterable {
    case verb
    case pid
    case maxDepth
    case maxNodes
    /// Whether this read wants the device in accessibility automation mode. Tri-state: omitted means
    /// observe without touching the device, which is what a host predating the field sends; `true` and
    /// `false` each assert that state. Omitted and `false` are different requests.
    case automationMode
    /// Reads through the accessibility translator's vocabulary rather than XCTest's. Off unless asked
    /// for: the two disagree on some screens, and which one a caller wants is not the reader's choice.
    case translatorVocabulary
    case snapshotTree
    /// The attributes the guest fetches per element. Omitted for a default read, which is what keeps
    /// that read byte-identical on the wire; the guest falls back to `Node.defaultFetchList`.
    case attributes
    /// Asks the guest to explain each unreachable element by hit-testing its centre. Omitted unless
    /// `occludedBy` was requested, so a read that does not want the explanation does not pay for it.
    case explainUnreachable
    case x
    case y
    case method
    case action
    case value
    case assertKey
    case assertValue

    /// The JSON object key the persistent transport sends this field under.
    var key: String { rawValue }

    /// The argv flag the one-shot transport sends it as, or nil for the one field that is not an option:
    /// the verb, which the CLI takes as its subcommand.
    var flag: String? {
      switch self {
      case .verb: nil
      case .pid: "--pid"
      case .maxDepth: "--max-depth"
      case .maxNodes: "--max-nodes"
      case .automationMode: "--automation-mode"
      case .translatorVocabulary: "--translator-vocabulary"
      case .snapshotTree: "--snapshot-tree"
      case .attributes: "--attributes"
      case .explainUnreachable: "--explain-unreachable"
      case .x: "--x"
      case .y: "--y"
      case .method: "--method"
      case .action: "--action"
      case .value: "--value"
      case .assertKey: "--assert-key"
      case .assertValue: "--assert-value"
      }
    }

    /// This field as the flag/value pair the guest's argv parser reads, which takes its arguments strictly
    /// two at a time — so a field that is not an option contributes neither half rather than a stray one.
    func argument(_ value: String) -> [String] {
      guard let flag else {
        return []
      }
      return [flag, value]
    }
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
