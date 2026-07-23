/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public enum FBDsymBundleType: Int {
  case xcTest
  case app
}

@objc public final class FBDsymInstallLinkToBundle: NSObject {

  @objc public let bundle_id: String
  @objc public let bundle_type: FBDsymBundleType

  @objc public init(_ bundle_id: String, bundle_type: FBDsymBundleType) {
    self.bundle_id = bundle_id
    self.bundle_type = bundle_type
    super.init()
  }
}
