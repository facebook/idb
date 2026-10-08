/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public let XCTestBootstrapErrorDomain = "com.facebook.XCTestBootstrap"

public let FBTestErrorDomain = "com.facebook.FBTestError"

@objc public enum XCTestBootstrapErrorCode: Int {
  case startupFailure = 0x3
  case lostConnection = 0x4
  case startupTimeout = 0x5
}

/// Errors raised by the Objective-C test manager, which cannot see the Swift domain constants.
@objc public final class XCTestBootstrapErrors: NSObject {

  /// A failure to start the test run, in `XCTestBootstrapErrorDomain`.
  @objc public static func startupFailure(_ description: String, underlyingError: NSError?) -> NSError {
    var userInfo: [String: Any] = [NSLocalizedDescriptionKey: description]
    userInfo[NSUnderlyingErrorKey] = underlyingError
    return NSError(domain: XCTestBootstrapErrorDomain, code: XCTestBootstrapErrorCode.startupFailure.rawValue, userInfo: userInfo)
  }

  /// A failure attributed to the test process rather than to idb, in `FBTestErrorDomain`.
  @objc public static func testFailure(_ description: String) -> NSError {
    NSError(domain: FBTestErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: description])
  }
}
