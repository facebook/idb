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
@objc(FBStatusBarOverride)
public final class FBStatusBarOverride: NSObject {

  /// Display time string, e.g. "9:41".
  @objc public var timeString: String?

  /// Data network type.
  @objc public var dataNetworkType: NSNumber?

  /// WiFi mode: 1=searching, 2=failed, 3=active.
  @objc public var wiFiMode: NSNumber?

  /// WiFi signal bars (0-3).
  @objc public var wiFiBars: NSNumber?

  /// Cellular mode: 0=notSupported, 1=searching, 2=failed, 3=active.
  @objc public var cellularMode: NSNumber?

  /// Cellular signal bars (0-4).
  @objc public var cellularBars: NSNumber?

  /// Cellular operator name.
  @objc public var operatorName: String?

  /// Battery state.
  @objc public var batteryState: NSNumber?

  /// Battery level (0-100).
  @objc public var batteryLevel: NSNumber?

  /// Whether to show "not charging" indicator.
  @objc public var showNotCharging: NSNumber?

  @objc public override init() {
    super.init()
  }
}
