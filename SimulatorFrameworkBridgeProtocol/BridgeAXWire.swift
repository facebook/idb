/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Accessibility vocabulary shared by the macOS host and simulator guest.
public enum BridgeAXWire {

  /// Per-node attribute keys — the exact keys `_XCTD_fetchAttributes:forElement:` accepts and echoes
  /// back in its per-element result dictionary.
  public enum Node: String, Codable, Sendable {
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
    /// The element's own centre. Read only to compare against `visiblePoint`; a divergence identifies a
    /// partially covered element.
    case centerPoint = "XC_kAXXCAttributeCenterPoint"
    case userInteractionEnabled = "XC_kAXXCAttributeIsUserInteractionEnabled"
    /// What a display-wide hit-test at an unreachable element's centre found. Reader-derived, not an
    /// `XC_kAXXC*` attribute: the guest hit-tests inline while it walks, sparing the host a round trip per
    /// unreachable element.
    case explainedBy = "FBExplainedBy"
    /// Whether the element is enabled, as the accessibility translator answers it. Reader-namespaced:
    /// XCTest's vocabulary has no counterpart, so only a read through the translator's vocabulary
    /// carries this key, and every other read reports `enabled` as an explicit null.
    case isEnabled = "FBIsEnabled"
    /// The translator's `role`, as the translator's own integer.
    ///
    /// Deliberately *not* mapped onto `elementType`, which carries `XCUIElementType` names: the mapping
    /// from these integers onto those names is only partly known.
    /// `AXRoleVocabulary.name(forTranslatorRole:)` maps the identified integers; the rest ride the
    /// wire unmapped.
    case translatorRole = "FBTranslatorRole"
    /// The translator's `subrole`, as its own integer. It refines the role rather than replacing it: a
    /// toggle is a check box with a switch subrole, a search field a text field with a search subrole.
    /// `AXRoleVocabulary.name(forTranslatorSubrole:)` maps the identified integers.
    case translatorSubrole = "FBTranslatorSubrole"
    /// The `UIAccessibilityTraits` bitmask, as the translator answers it. Carried raw: the trait
    /// constants live in a macOS-only header the guest cannot import, and nothing decodes it yet.
    case traits = "FBTraits"
    /// A per-element identity from the translator, stable while the element lives — so two reads can be
    /// compared element by element. The `XC_kAXXCAttribute*` namespace has no counterpart.
    case elementIdentity = "FBElementIdentity"
    case attributeReadFailures = "FBAttributeReadFailures"

    /// The attribute list a read requests for each element when it names none of its own. Membership
    /// *and* order are part of the contract: the guest fetches and echoes back exactly this sequence.
    ///
    /// A read may name a different list through `Request.attributes`; both sides fall back to this
    /// when it does not.
    public static let defaultFetchList: [String] = [
      elementType, elementBaseType, label, value, identifier, frame, automationType, children,
    ].map(\.rawValue)

    /// The attributes `AXKeys.interactable` is derived from. Fetched only when that key is requested.
    public static let interactableAttributes: [Node] = [.isVisible, .visiblePoint, .centerPoint, .userInteractionEnabled]

  }

  /// Top-level keys of the guest's `{ ok, tree | error, ... }` response envelope, parsed by
  /// `AXTreeRead`.
  public enum Envelope: String, Codable, Sendable {
    case method
    case ok
    case enabled
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
  /// phases are not here: it measures those itself.
  public enum Phase: String, Codable, Sendable {
    case traverse = "traverse_ms"
    case machRoundTrips = "mach_round_trips"
  }

  /// Keys of the envelope's `automation` object: the device's accessibility automation mode as it stood
  /// for the read, and whether the read changed it.
  public enum Automation: String, Codable, Sendable {
    case enabled
    case asserted
  }

  /// What class of thing went wrong, as the guest's `error_kind` reports it.
  ///
  /// The kind decides what the host *tells* the caller — which typed error it raises and whether any
  /// remedy applies — while the envelope's `error` carries the detail. An unknown or absent kind
  /// degrades to a generic reader failure rather than failing to parse.
  public enum ErrorKind: String, Codable, Sendable, CaseIterable {
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
  public enum Verb: String, Codable, Sendable, CaseIterable {
    case displays
    case describe
    case hitTest = "hittest"
    case perform
    case setValue = "setvalue"
    case settingsGet = "settings-get"
    case settingsSet = "settings-set"
  }

  /// The fields of a request, in both spellings the guest accepts them in.
  ///
  /// One case per field: the persistent transport sends JSON and the one-shot transport sends argv for
  /// the *same* request, so the two renderings are declared together and cannot drift.
  public enum Request: String, Codable, Sendable, CaseIterable {
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
    /// The attributes the guest fetches per element. Omitted for a default read; the guest falls back
    /// to `Node.defaultFetchList`.
    case attributes
    /// Asks the guest to explain each unreachable element by hit-testing its centre. Omitted unless
    /// `occludedBy` was requested, so a read that does not want the explanation does not pay for it.
    case explainUnreachable
    case x
    case y
    case method
    case action
    case value
    case setting
    case enabled
    case assertKey
    case assertValue

    /// The JSON object key the persistent transport sends this field under.
    public var key: String { rawValue }

    /// The argv flag the one-shot transport sends it as, or nil for the one field that is not an option:
    /// the verb, which the CLI takes as its subcommand.
    public var flag: String? {
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
      case .setting: "--setting"
      case .enabled: "--enabled"
      case .assertKey: "--assert-key"
      case .assertValue: "--assert-value"
      }
    }

    /// This field as the flag/value pair the guest's argv parser reads, which takes its arguments strictly
    /// two at a time — so a field that is not an option contributes neither half rather than a stray one.
    public func argument(_ value: String) -> [String] {
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
  /// happens.
  public enum Action: String, Codable, Sendable, CaseIterable {
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
