/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public let FBIDBErrorDomain: String = "com.facebook.idb"

@objc public final class FBIDBError: FBControlCoreError {

  public override init() {
    super.init()
    self.inDomain(FBIDBErrorDomain)
  }
}
