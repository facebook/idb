/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public let XCTestBootstrapErrorDomain = "com.facebook.XCTestBootstrap"

public let FBTestErrorDomain = "com.facebook.FBTestError"

@objc public enum XCTestBootstrapErrorCode: Int {
  case startupFailure = 0x3
  case lostConnection = 0x4
  case startupTimeout = 0x5
}

@objc public final class XCTestBootstrapError: ControlCoreError {
  public required init() {
    super.init()
    self.inDomain(XCTestBootstrapErrorDomain)
  }
}

public final class XCTestError: ControlCoreError {
  public required init() {
    super.init()
    self.inDomain(FBTestErrorDomain)
  }
}
