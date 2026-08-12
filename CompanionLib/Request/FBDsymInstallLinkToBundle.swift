/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum FBDsymBundleType {
  case xcTest
  case app
}

public struct FBDsymInstallLinkToBundle {

  public let bundleID: String
  public let bundleType: FBDsymBundleType

  public init(bundleID: String, bundleType: FBDsymBundleType) {
    self.bundleID = bundleID
    self.bundleType = bundleType
  }
}
