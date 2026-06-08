/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Options for fetching remote process elements (e.g., WebView content).
/// Remote elements are in separate processes and require grid-based hit-testing.
///
/// Still read by the Objective-C serializer in `FBSimulatorControl`, so this
/// stays an `@objc` class with mutable properties and the ObjC class name. It
/// will become a Swift `struct` once the serializer is Swift.
@objc(FBAccessibilityRemoteContentOptions)
public final class FBAccessibilityRemoteContentOptions: NSObject, NSCopying {

  /// Grid step size in points for sampling. Smaller = more thorough but slower. Default: 50.0
  @objc public var gridStepSize: CGFloat = 50.0

  /// Region to sample. `.null` = full screen (default).
  @objc public var region: CGRect = .null

  /// Maximum points to sample. 0 = unlimited (default).
  @objc public var maxPoints: UInt = 0

  @objc public override init() {
    super.init()
  }

  /// Creates options with default values.
  @objc(defaultOptions)
  public static func `default`() -> FBAccessibilityRemoteContentOptions {
    FBAccessibilityRemoteContentOptions()
  }

  public func copy(with zone: NSZone? = nil) -> Any {
    let copy = FBAccessibilityRemoteContentOptions()
    copy.gridStepSize = gridStepSize
    copy.region = region
    copy.maxPoints = maxPoints
    return copy
  }

  public override var description: String {
    let regionString = region.isNull ? "fullscreen" : "\(region)"
    return "<\(NSStringFromClass(type(of: self))): stepSize=\(gridStepSize), region=\(regionString), maxPoints=\(maxPoints)>"
  }
}

/// Request options for accessibility operations. Consolidates all parameters
/// needed for an accessibility query.
///
/// Still read by the Objective-C serializer in `FBSimulatorControl`, so this
/// stays an `@objc` class with mutable properties and the ObjC class name. It
/// will become a Swift `struct` (with typed `[FBAXKeys]` keys) once the
/// serializer is Swift.
@objc(FBAccessibilityRequestOptions)
public final class FBAccessibilityRequestOptions: NSObject, NSCopying {

  /// If `true`, data is returned in nested format with children; otherwise flat. Default: `false`.
  @objc public var nestedFormat: Bool = false

  /// Set of string keys to filter which properties are returned.
  /// Defaults to `FBAXKeys.defaultSet` (the standard keys). `nil` means all default keys.
  @objc public var keys: Set<String>?

  /// Log accessibility requests and responses to the simulator's logger. Default: `false`.
  @objc public var enableLogging: Bool = false

  /// Collect profiling data (element counts, timing metrics). Default: `false`.
  @objc public var enableProfiling: Bool = false

  /// Enable frame coverage calculation during traversal. Default: `false`.
  @objc public var collectFrameCoverage: Bool = false

  /// Options for remote content fetching. `nil` (default) means remote content is not fetched.
  @objc public var remoteContentOptions: FBAccessibilityRemoteContentOptions?

  @objc public override init() {
    self.keys = Set(FBAXKeys.defaultSet.map(\.rawValue))
    super.init()
  }

  /// Creates options with default values.
  @objc(defaultOptions)
  public static func `default`() -> FBAccessibilityRequestOptions {
    FBAccessibilityRequestOptions()
  }

  public func copy(with zone: NSZone? = nil) -> Any {
    let copy = FBAccessibilityRequestOptions()
    copy.nestedFormat = nestedFormat
    copy.keys = keys
    copy.enableLogging = enableLogging
    copy.enableProfiling = enableProfiling
    copy.collectFrameCoverage = collectFrameCoverage
    copy.remoteContentOptions = remoteContentOptions?.copy() as? FBAccessibilityRemoteContentOptions
    return copy
  }

  public override var description: String {
    "<\(NSStringFromClass(type(of: self))): nested=\(nestedFormat), keys=\(String(describing: keys)), logging=\(enableLogging), profiling=\(enableProfiling), collectFrameCoverage=\(collectFrameCoverage), remote=\(String(describing: remoteContentOptions))>"
  }
}
