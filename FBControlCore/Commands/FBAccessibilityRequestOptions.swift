/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// Options for fetching remote process elements (e.g., WebView content).
/// Remote elements are in separate processes and require grid-based hit-testing.
public struct FBAccessibilityRemoteContentOptions: Sendable {

  /// Grid step size in points for sampling. Smaller = more thorough but slower. Default: 50.0
  public var gridStepSize: CGFloat

  /// Region to sample. `.null` = full screen (default).
  public var region: CGRect

  /// Maximum points to sample. 0 = unlimited (default).
  public var maxPoints: UInt

  public init(gridStepSize: CGFloat = 50.0, region: CGRect = .null, maxPoints: UInt = 0) {
    self.gridStepSize = gridStepSize
    self.region = region
    self.maxPoints = maxPoints
  }
}

extension FBAccessibilityRemoteContentOptions: CustomStringConvertible {
  public var description: String {
    let regionString = region.isNull ? "fullscreen" : "\(region)"
    return "<FBAccessibilityRemoteContentOptions: stepSize=\(gridStepSize), region=\(regionString), maxPoints=\(maxPoints)>"
  }
}

/// Filters which elements a describe-all read returns, applied in the shared serializer so both the
/// accessibility and axbridge backends honor it identically. The raw values are the filter's
/// canonical tokens — what a CLI accepts — so a consumer selects a filter without re-declaring the
/// case list.
public enum FBAccessibilityElementFilter: String, Sendable, CaseIterable {
  /// Every element in the tree (default).
  case all
  /// Elements that can actually be interacted with.
  ///
  /// Answered from the backend's own verdict where there is one: an element survives only when
  /// `interactable` reports it actionable, so anything covered, disabled, zero-sized or not taking
  /// touches is dropped however button-like it looks. For a caller choosing something to tap, this is
  /// the list worth choosing from.
  ///
  /// On a backend that cannot judge interactability — the legacy accessibility path, which has no
  /// counterpart for the attributes the verdict is derived from — it falls back to a structural
  /// heuristic: keep an element carrying a label, an identifier, or an actionable role.
  ///
  /// It drops occluded elements. To see a covered element and why it is blocked, read with `.all` and
  /// `--key interactable`. Marker lookup and writes are unfiltered, so this never affects whether an
  /// element can be found or acted on — only what a describe reports.
  case interactable

  /// The attributes this filter reads to decide what to keep.
  ///
  /// The filter runs over the serialized model, so an attribute the read did not serialize is one it
  /// cannot match on — an element would be dropped for lacking a label that was simply never fetched.
  /// `serializationKeys` unions these in so narrowing `--key` narrows the *output* without also
  /// changing which elements survive.
  public var requiredKeys: Set<FBAXKeys> {
    switch self {
    case .all:
      return []
    case .interactable:
      // Structural signals only, never the verdict: including `interactable` here would force fetching
      // the reachability attributes, which the application answers by hit-testing every node. When the
      // read serialized the verdict (`--key interactable`) the filter uses it, so occluded elements are
      // dropped; otherwise it matches on label, identifier and role.
      return [.label, .uniqueID, .role]
    }
  }
}

/// A substring search a describe-all read narrows its elements by: report only the elements whose
/// `key` value contains `value`.
///
/// Distinct from `FBAccessibilityElementQuery.marker`, which selects exactly one element and fails
/// when there is none. A match narrows a list: no match is an empty list, not an error, and every
/// element that matches is reported rather than the first.
///
/// Like the filter it runs beside, this reads the *serialized* element, so `key`'s attribute has to be
/// among the keys the read serialized — `serializationKeys` unions it in for that reason.
public struct FBAccessibilityMatch: Sendable, Equatable {

  /// The substring an element's `key` value must contain. Never empty: an empty match reports every
  /// element, which is the absence of a match rather than a match that succeeds everywhere, so callers
  /// express that by passing no match at all.
  public let value: String

  /// Which attribute the substring is compared against. Defaults to `.label`, the attribute all but a
  /// fraction of real lookups search on.
  public let key: FBAXSearchableKey

  /// Compare case-insensitively. Opt-in on both reads and marker writes; the default stays
  /// case-sensitive everywhere.
  public let ignoresCase: Bool

  /// Nil for an empty value, so "the caller passed no match" and "the caller passed an empty one" reach
  /// the filter as the same thing rather than as a predicate that keeps everything by accident.
  public init?(value: String, key: FBAXSearchableKey = .label, ignoresCase: Bool = false) {
    guard !value.isEmpty else {
      return nil
    }
    self.value = value
    self.key = key
    self.ignoresCase = ignoresCase
  }

  /// Whether a serialized attribute value satisfies this match. Nil — an attribute the element does not
  /// carry, or that the read did not serialize — never matches.
  public func matches(_ candidate: String?) -> Bool {
    guard let candidate else {
      return false
    }
    guard ignoresCase else {
      return candidate.contains(value)
    }
    return candidate.range(of: value, options: .caseInsensitive) != nil
  }
}

extension FBAccessibilityMatch: CustomStringConvertible {
  public var description: String {
    "<FBAccessibilityMatch: \(key.rawValue) contains '\(value)'\(ignoresCase ? " (ignoring case)" : "")>"
  }
}

/// How a read traverses the application, and therefore which set of attributes the returned elements
/// carry.
///
/// Two kinds of choice share this enum. `viewHierarchy` and `semantic` choose what is read, and neither
/// is better than the other — they answer different questions. `viewHierarchy` returns the view tree the
/// app built: deep, structural, every container; use it for structural assertions. `semantic` returns
/// what an accessibility client sees: flat and labelled; use it to ask what a user can interact with.
/// `singleFetch` is not a third answer to that question — it returns the same tree and attributes as
/// `viewHierarchy`, fetched in one call instead of one per node, so it is cheaper on large trees.
///
/// Chosen per read rather than per backend, and kept separate from persistence and frontmost resolution:
/// traversal, transport and frontmost are independent.
///
/// **A reachability verdict is scoped to what the strategy returned, not to what is on screen.**
/// `semantic` typically returns fewer elements than `viewHierarchy`, so "reachable 100%" from a
/// semantic read means "everything this read found is reachable", not "everything on the screen is
/// reachable". A strategy can be right about reachability and incomplete about content at once.
///
/// Which strategy returns more is a property of the screen, not of the strategies: they read different
/// child relations, and an app can leave either one wrong (a stale automation-elements override, for
/// example). Neither strategy's count is the denominator the other should be measured against.
///
/// A strategy need not answer everything for every element: `semantic` answers `type` only for the
/// translator roles that have been identified. A key it cannot always satisfy is warned about rather than
/// silently absent, so "the app set no type" stays distinguishable from "this read could not ask".
public enum FBAXTraversal: String, Sendable, CaseIterable {
  case viewHierarchy = "view-hierarchy"
  case semantic = "semantic"
  /// Reads the whole bounded subtree in one call instead of one call per node. The tree and the
  /// attributes are the same; the difference is that the application is asked once rather than N times.
  case singleFetch = "single-fetch"

  /// The keys this traversal cannot answer for every element, whatever the caller asks for.
  ///
  /// A key is listed when the traversal itself — not the app — can leave an element without it.
  /// `semantic` answers `type` from the translator's own role numbering, and only the identified roles
  /// map onto an `XCUIElementType` name, so a missing type on one of its elements may mean the read could
  /// not ask rather than that the element has no type.
  public var unsatisfiableKeys: Set<FBAXKeys> {
    switch self {
    case .viewHierarchy: []
    case .semantic: [.type]
    // Answers the same keys as the walk, except reachability — and that is a refusal in `describeTree`,
    // not an entry here: this list means "may be missing per element", and a fetch that cannot return at
    // all is not that.
    case .singleFetch: []
    }
  }
}

/// What a read asks to be traversed with: a traversal named outright, or `auto` — which names none and
/// leaves the choice to the backend serving the read.
///
/// A type of its own rather than a fourth `FBAXTraversal` case: `auto` is a request, not a traversal a
/// backend can perform. Everything past the resolution — the guest's argv, the unsatisfiable-key
/// warning, the profile — takes an `FBAXTraversal`, so "undecided" cannot be sent to a guest or reported
/// as the walk that happened.
public enum FBAXTraversalStrategy: String, Sendable, CaseIterable {
  /// Let the backend serving the read choose. Resolved by the backend, not here, because the cheapest
  /// traversal differs per backend; a profiled read reports which one ran.
  case auto
  case viewHierarchy = "view-hierarchy"
  case semantic = "semantic"
  case singleFetch = "single-fetch"

  /// The traversal this names outright, or nil for `auto`, which only a backend can resolve.
  public var traversal: FBAXTraversal? {
    switch self {
    case .auto: nil
    case .viewHierarchy: .viewHierarchy
    case .semantic: .semantic
    case .singleFetch: .singleFetch
    }
  }
}

/// Request options for accessibility operations. Consolidates all parameters needed for a query.
public struct FBAccessibilityRequestOptions: Sendable {

  /// How the read is rendered. Default: `.default` (a flat array).
  public var format: FBAccessibilityOutputFormat

  /// The attribute keys a read should actually fetch.
  ///
  /// `complete` reports two attributes only through their canonical counterparts — the stringified
  /// `AXFrame` through the `frame` object, and the raw `role` through the normalized `type` — so a
  /// caller asking for either would otherwise get nothing back for it. Reading the counterpart too
  /// keeps "an attribute you asked for is present in the output" true under that format.
  ///
  /// The enrichers that run over the serialized model widen it too. They read the model rather than the
  /// live element, so an attribute the read did not serialize is one they cannot see: a narrow `--key`
  /// would otherwise silently disable them rather than narrow the output. For those the cost is only in
  /// bytes — the walk fetches the frame for every node regardless of the key set.
  ///
  /// That is not true of every widening: `interactable` and `occludedBy` are costly to fetch — see
  /// `FBAXKeys.interactable`.
  public var serializationKeys: Set<FBAXKeys> {
    Self.serializationKeys(
      for: keys, format: format, filter: filter, match: match, collectFrameCoverage: collectFrameCoverage
    )
  }

  /// The same expansion over an arbitrary key set, for the marker read — which unions the key it
  /// searched on and must expand that too, or `--match-key role` matches on an attribute `complete`
  /// then reports under neither name.
  public func serializationKeys(including extraKeys: Set<FBAXKeys>) -> Set<FBAXKeys> {
    Self.serializationKeys(
      for: keys.union(extraKeys), format: format, filter: filter, match: match,
      collectFrameCoverage: collectFrameCoverage
    )
  }

  /// The attributes a frame-coverage calculation reads: the geometry to measure, the type identifying
  /// the application root it must skip, and the label its `content` dimension counts as perceivable.
  private static let frameCoverageKeys: Set<FBAXKeys> = [.frameDict, .type, .label]

  private static func serializationKeys(
    for keys: Set<FBAXKeys>,
    format: FBAccessibilityOutputFormat,
    filter: FBAccessibilityElementFilter,
    match: FBAccessibilityMatch?,
    collectFrameCoverage: Bool
  ) -> Set<FBAXKeys> {
    var expanded = keys
    // `occluded_by` enriches `interactable`'s reasons rather than emitting a field of its own, so asking
    // for it asks for the thing it enriches — and for the frame, since the hit-test it performs is aimed
    // at the element's centre and has nowhere else to get one.
    if expanded.contains(.occludedBy) {
      expanded.formUnion(FBAXKeys.occluderIdentityKeys)
    }
    if format == .complete {
      if keys.contains(.frame) {
        expanded.insert(.frameDict)
      }
      if keys.contains(.role) {
        expanded.insert(.type)
      }
    }
    if filter != .all {
      expanded.formUnion(filter.requiredKeys)
    }
    // Same reason as the filter's `requiredKeys`, and as the marker read's `including:`: the match runs
    // over the serialized model, so an attribute the read did not fetch is one it cannot match on —
    // `--key frame --match Buy` would otherwise report nothing rather than the buy button's frame.
    if let match {
      expanded.insert(match.key.serializationKey)
      // `complete` reports `role` only as the normalized `type`, so matching on the raw attribute needs
      // the counterpart too — the same widening the format arm above performs for a requested key.
      if format == .complete, match.key.serializationKey == .role {
        expanded.insert(.type)
      }
    }
    if collectFrameCoverage {
      expanded.formUnion(frameCoverageKeys)
    }
    return expanded
  }

  /// Whether the serializer builds a tree rather than a flat list. Derived from `format` — every format
  /// but `.default` carries children — so the two can never disagree.
  public var nestedFormat: Bool { format != .default }

  /// Which properties a read returns. Defaults to `FBAXKeys.defaultSet` (the standard keys); pass an
  /// explicit set to narrow it. Not optional: "unset" and "the default set" are the same request.
  public var keys: Set<FBAXKeys>

  /// Log accessibility requests and responses to the simulator's logger. Default: `false`.
  public var enableLogging: Bool

  /// Collect profiling data (element counts, timing metrics). Default: `false`.
  public var enableProfiling: Bool

  /// Enable frame coverage calculation during traversal. Default: `false`.
  public var collectFrameCoverage: Bool

  /// Options for remote content fetching. `nil` (default) means remote content is not fetched.
  public var remoteContentOptions: FBAccessibilityRemoteContentOptions?

  /// Which elements to include in a describe-all read. Default: `.all`.
  public var filter: FBAccessibilityElementFilter

  /// A substring search narrowing which elements a describe-all read reports. `nil` (default) reports
  /// every element the filter kept.
  ///
  /// Composes with `filter` rather than replacing it: `filter` decides what is worth reporting at all,
  /// the match decides which of those the caller asked about.
  public var match: FBAccessibilityMatch?

  /// How the read asks to traverse. Default: `.auto`, so a caller who does not choose gets whatever
  /// the backend serving them does best.
  public var traversalStrategy: FBAXTraversalStrategy

  /// The keys this read asked for that the traversal it was served by cannot answer for every element.
  /// Empty for the default traversal.
  ///
  /// Takes the traversal rather than reading `traversalStrategy`, because that may name none: what a read
  /// could not ask about is a property of the walk that happened, not of what was asked for.
  public func unsatisfiableKeys(for traversal: FBAXTraversal) -> Set<FBAXKeys> {
    serializationKeys.intersection(traversal.unsatisfiableKeys)
  }

  public init(
    format: FBAccessibilityOutputFormat = .default,
    keys: Set<FBAXKeys> = FBAXKeys.defaultSet,
    enableLogging: Bool = false,
    enableProfiling: Bool = false,
    collectFrameCoverage: Bool = false,
    remoteContentOptions: FBAccessibilityRemoteContentOptions? = nil,
    filter: FBAccessibilityElementFilter = .all,
    match: FBAccessibilityMatch? = nil,
    traversalStrategy: FBAXTraversalStrategy = .auto
  ) {
    self.format = format
    self.keys = keys
    self.enableLogging = enableLogging
    self.enableProfiling = enableProfiling
    self.collectFrameCoverage = collectFrameCoverage
    self.remoteContentOptions = remoteContentOptions
    self.filter = filter
    self.match = match
    self.traversalStrategy = traversalStrategy
  }
}

extension FBAccessibilityRequestOptions: CustomStringConvertible {
  public var description: String {
    "<FBAccessibilityRequestOptions: format=\(format.rawValue), keys=\(keys), logging=\(enableLogging), profiling=\(enableProfiling), collectFrameCoverage=\(collectFrameCoverage), remote=\(String(describing: remoteContentOptions)), filter=\(filter.rawValue), match=\(match.map(String.init(describing:)) ?? "none"), traversal=\(traversalStrategy.rawValue)>"
  }
}
