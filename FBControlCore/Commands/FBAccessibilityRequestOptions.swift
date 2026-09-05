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

/// Filters which elements a describe-all read returns. Applied in the shared serializer so every backend
/// honors it identically; raw values are the CLI tokens.
public enum FBAccessibilityElementFilter: String, Sendable, CaseIterable {
  /// Every element in the tree (default).
  case all
  /// Elements that can be interacted with. Uses the backend's `interactable` verdict when the read serialized
  /// it (covered, disabled or zero-sized elements are dropped); otherwise falls back to a structural
  /// heuristic: has a label, an identifier, or an actionable role. Affects only what a describe reports —
  /// marker lookup and writes are unfiltered.
  case interactable

  /// The attributes the filter matches on; `serializationKeys` unions these in so a narrow `--key` cannot
  /// starve the filter.
  var requiredKeys: Set<FBAXKeys> {
    switch self {
    case .all:
      return []
    case .interactable:
      // Never `.interactable`: fetching the verdict hit-tests every node. It is used only when the read
      // serialized it anyway.
      return [.label, .uniqueID, .role]
    }
  }
}

/// A substring search narrowing a describe-all read to elements whose `key` value contains `value`.
/// Unlike `FBAccessibilityElementQuery.marker`, no match is an empty list rather than an error, and
/// every matching element is reported.
public struct FBAccessibilityMatch: Sendable, Equatable {

  /// The substring an element's `key` value must contain. Never empty (see `init?`).
  public let value: String

  /// The attribute the substring is compared against.
  public let key: FBAXSearchableKey

  /// Compare case-insensitively.
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

/// How a read traverses the application, which determines the attributes elements carry.
/// `viewHierarchy` returns the app's view tree (deep, every container); `semantic` returns what an
/// accessibility client sees (flat, labelled); `singleFetch` returns the same tree as `viewHierarchy`,
/// fetched once per drawing process rather than once per node. The strategies read different child
/// relations, so neither's element count is a baseline for the other, and a reachability verdict covers
/// only what the strategy returned, not everything on screen.
public enum FBAXTraversal: String, Sendable, CaseIterable {
  case viewHierarchy = "view-hierarchy"
  case semantic = "semantic"
  /// One fetch for the application plus one per subtree another process draws (a web view, picker or
  /// autofill sheet), which a single fetch cannot cross into.
  case singleFetch = "single-fetch"

  /// Keys this traversal cannot answer for every element: `semantic` maps only identified translator roles
  /// onto an `XCUIElementType` name, so `type` may be missing.
  public var unsatisfiableKeys: Set<FBAXKeys> {
    switch self {
    case .viewHierarchy: []
    case .semantic: [.type]
    // Reachability is refused outright by `describeTree`, not missing per element.
    case .singleFetch: []
    }
  }
}

/// The traversal a read asks for, or `auto` to let the serving backend choose. Kept apart from
/// `FBAXTraversal` so an unresolved request can never be sent to a guest or reported as the walk that ran.
public enum FBAXTraversalStrategy: String, Sendable, CaseIterable {
  /// Let the serving backend choose; a profiled read reports which traversal ran.
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

/// Request options for accessibility operations.
public struct FBAccessibilityRequestOptions: Sendable {

  /// How the read is rendered. Default: `.default` (a flat array).
  public var format: FBAccessibilityOutputFormat

  /// The keys a read must actually fetch: `keys` widened with whatever the format, filter, match and
  /// frame-coverage enrichers read from the serialized model, so narrowing `--key` narrows the output
  /// without silently disabling them. Some widenings are costly — see `FBAXKeys.interactable`.
  public var serializationKeys: Set<FBAXKeys> {
    Self.serializationKeys(
      for: keys, format: format, filter: filter, match: match, collectFrameCoverage: collectFrameCoverage
    )
  }

  /// `serializationKeys` over `keys` plus `extraKeys`; the marker read passes the key it searched on.
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
    // The match runs over the serialized model, so its key must be fetched.
    if let match {
      expanded.insert(match.key.serializationKey)
      // Under `complete`, `role` is reported only as `type`.
      if format == .complete, match.key.serializationKey == .role {
        expanded.insert(.type)
      }
    }
    if collectFrameCoverage {
      expanded.formUnion(frameCoverageKeys)
    }
    return expanded
  }

  /// Whether the serializer builds a tree: every format but `.default` carries children.
  public var nestedFormat: Bool { format != .default }

  /// Which properties a read returns.
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

  /// How the read asks to traverse.
  public var traversalStrategy: FBAXTraversalStrategy

  /// The requested keys the given traversal cannot answer for every element.
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
