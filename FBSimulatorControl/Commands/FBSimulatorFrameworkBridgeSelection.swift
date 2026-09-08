/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Which bundled `SimulatorFrameworkBridge` guest a target can run.
///
/// A guest records the platform it was built for in `LC_BUILD_VERSION`, and a simulator's dyld refuses
/// one built for another, so the companion ships one per platform rather than one binary for all.
enum FBSimulatorFrameworkBridgeSelection {

  static func resourceName(for productFamily: FBControlCoreProductFamily) -> String {
    switch productFamily {
    case .familyAppleTV:
      return "SimulatorFrameworkBridge-tvOS"
    // Only Apple TV has a guest of its own; every other family runs the iOS binary.
    case .familyiPhone, .familyiPad, .familyAppleWatch, .familyMac, .familyUnknown:
      return "SimulatorFrameworkBridge-iOS"
    @unknown default:
      return "SimulatorFrameworkBridge-iOS"
    }
  }
}

extension FBSimulator {

  /// The path to the guest binary this simulator can run, or nil when it is not bundled.
  var frameworkBridgePath: String? {
    BundledResources.path(
      forItem: FBSimulatorFrameworkBridgeSelection.resourceName(for: productFamily))
  }
}
