/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

/// Bridge for killswitch from objc world. Should be subset of `IDBFeature`. Use from objc
@objc(FBIDBFeatureKey) enum IDBFeatureBridge: Int {
  case grpcEndpoint

  fileprivate var nativeValue: IDBFeature {
    switch self {
    case .grpcEndpoint:
      return .grpcEndpoint
    }
  }
}

@objc(FBIDBKillswitch) class IDBKillswitchBridge: NSObject {

  private let idbKillswitch: IDBKillswitch

  init(idbKillswitch: IDBKillswitch) {
    self.idbKillswitch = idbKillswitch
  }

  /// - Returns: NSNumber initialized with boolean value
  @objc func disabledWith(_ feature: IDBFeatureBridge) -> FBFuture<NSNumber> {
    return Task.fbFuture {
      await NSNumber(value: self.idbKillswitch.disabled(feature.nativeValue))
    }
  }
}
