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

/// Request options for accessibility operations. Consolidates all parameters
/// needed for an accessibility query.
public struct FBAccessibilityRequestOptions: Sendable {

  /// If `true`, data is returned in nested format with children; otherwise flat. Default: `false`.
  public var nestedFormat: Bool

  /// Set of keys to filter which properties are returned.
  /// Defaults to `FBAXKeys.defaultSet` (the standard keys).
  public var keys: Set<FBAXKeys>?

  /// Log accessibility requests and responses to the simulator's logger. Default: `false`.
  public var enableLogging: Bool

  /// Collect profiling data (element counts, timing metrics). Default: `false`.
  public var enableProfiling: Bool

  /// Enable frame coverage calculation during traversal. Default: `false`.
  public var collectFrameCoverage: Bool

  /// Options for remote content fetching. `nil` (default) means remote content is not fetched.
  public var remoteContentOptions: FBAccessibilityRemoteContentOptions?

  /// RocketSim addition: maximum serialization depth. `0` (default) is unlimited; `1` serializes
  /// only the resolved element without descending into children. Point queries that only inspect
  /// the top-level match use this to skip the expensive merged-children fan-out.
  public var maxDepth: UInt

  public init(
    nestedFormat: Bool = false,
    keys: Set<FBAXKeys>? = FBAXKeys.defaultSet,
    enableLogging: Bool = false,
    enableProfiling: Bool = false,
    collectFrameCoverage: Bool = false,
    remoteContentOptions: FBAccessibilityRemoteContentOptions? = nil,
    maxDepth: UInt = 0
  ) {
    self.nestedFormat = nestedFormat
    self.keys = keys
    self.enableLogging = enableLogging
    self.enableProfiling = enableProfiling
    self.collectFrameCoverage = collectFrameCoverage
    self.remoteContentOptions = remoteContentOptions
    self.maxDepth = maxDepth
  }
}

extension FBAccessibilityRequestOptions: CustomStringConvertible {
  public var description: String {
    "<FBAccessibilityRequestOptions: nested=\(nestedFormat), keys=\(String(describing: keys)), logging=\(enableLogging), profiling=\(enableProfiling), collectFrameCoverage=\(collectFrameCoverage), remote=\(String(describing: remoteContentOptions))>"
  }
}
