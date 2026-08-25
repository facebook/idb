/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Represents a set of status bar overrides for deterministic screenshots.
/// Non-nil NSNumber properties are applied as overrides; nil properties are left unchanged.
/// All SimDevice status bar methods use raw NSInteger parameters (same as appearance/content size).
public struct FBStatusBarOverride: Sendable {

  /// Display time string, e.g. "9:41".
  public var timeString: String?

  /// Data network type.
  public var dataNetworkType: NSNumber?

  /// WiFi mode: 1=searching, 2=failed, 3=active.
  public var wiFiMode: NSNumber?

  /// WiFi signal bars (0-3).
  public var wiFiBars: NSNumber?

  /// Cellular mode: 0=notSupported, 1=searching, 2=failed, 3=active.
  public var cellularMode: NSNumber?

  /// Cellular signal bars (0-4).
  public var cellularBars: NSNumber?

  /// Cellular operator name.
  public var operatorName: String?

  /// Battery state.
  public var batteryState: NSNumber?

  /// Battery level (0-100).
  public var batteryLevel: NSNumber?

  /// Whether to show "not charging" indicator.
  public var showNotCharging: NSNumber?

  public init() {}
}
