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
/// accessibility and remote-automation backends honor it identically.
public enum FBAccessibilityElementFilter: Sendable {
  /// Every element in the tree (default).
  case all
  /// Only "interactable" elements — those with a label, an identifier, or an actionable role
  /// (Button, Cell, TextField, …). Unlabeled structural container nodes are dropped; in nested output
  /// a dropped container's matching descendants are hoisted to its nearest kept ancestor.
  case interactable
}

/// Request options for accessibility operations. Consolidates all parameters
/// needed for an accessibility query.
public struct FBAccessibilityRequestOptions: Sendable {

  /// How the read is rendered. Default: `.default` (a flat array).
  public var format: FBAccessibilityOutputFormat

  /// Whether the serializer builds a tree rather than a flat list. Derived from `format` — every format
  /// but `.default` carries children — so the two can never disagree.
  public var nestedFormat: Bool { format != .default }

  /// Which properties a read returns. Defaults to `FBAXKeys.defaultSet` (the standard keys); pass an
  /// explicit set to narrow it. Not optional: "unset" and "the default set" are the same request, and
  /// making that one value keeps every backend from inventing its own reading of an absent set.
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

  public init(
    format: FBAccessibilityOutputFormat = .default,
    keys: Set<FBAXKeys> = FBAXKeys.defaultSet,
    enableLogging: Bool = false,
    enableProfiling: Bool = false,
    collectFrameCoverage: Bool = false,
    remoteContentOptions: FBAccessibilityRemoteContentOptions? = nil,
    filter: FBAccessibilityElementFilter = .all
  ) {
    self.format = format
    self.keys = keys
    self.enableLogging = enableLogging
    self.enableProfiling = enableProfiling
    self.collectFrameCoverage = collectFrameCoverage
    self.remoteContentOptions = remoteContentOptions
    self.filter = filter
  }
}

extension FBAccessibilityRequestOptions: CustomStringConvertible {
  public var description: String {
    "<FBAccessibilityRequestOptions: format=\(format.rawValue), keys=\(keys), logging=\(enableLogging), profiling=\(enableProfiling), collectFrameCoverage=\(collectFrameCoverage), remote=\(String(describing: remoteContentOptions))>"
  }
}
