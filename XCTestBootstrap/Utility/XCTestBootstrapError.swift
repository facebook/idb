/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class XCTestBootstrapError: FBControlCoreError {
  public override init() {
    super.init()
    self.inDomain(XCTestBootstrapErrorDomain)
  }
}

@objc public final class FBXCTestError: FBControlCoreError {
  public override init() {
    super.init()
    self.inDomain(FBTestErrorDomain)
  }
}
