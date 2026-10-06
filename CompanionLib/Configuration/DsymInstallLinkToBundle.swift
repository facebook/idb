/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum DsymBundleType: Sendable {
  case xcTest
  case app
}

public struct DsymInstallLinkToBundle: Sendable {

  public let bundleID: String
  public let bundleType: DsymBundleType

  public init(bundleID: String, bundleType: DsymBundleType) {
    self.bundleID = bundleID
    self.bundleType = bundleType
  }
}
