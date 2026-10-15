/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public let XCTestBootstrapErrorDomain = "com.facebook.XCTestBootstrap"

public let TestFailureErrorDomain = "com.facebook.FBTestError"

public enum XCTestBootstrapErrorCode: Int {
  case startupFailure = 0x3
  case lostConnection = 0x4
  case startupTimeout = 0x5
}

/// The `NSError`s the test manager reports, in the domains above.
public enum XCTestBootstrapErrors {

  /// A failure to start the test run, in `XCTestBootstrapErrorDomain`.
  public static func startupFailure(_ description: String, underlyingError: NSError?) -> NSError {
    var userInfo: [String: Any] = [NSLocalizedDescriptionKey: description]
    userInfo[NSUnderlyingErrorKey] = underlyingError
    return NSError(domain: XCTestBootstrapErrorDomain, code: XCTestBootstrapErrorCode.startupFailure.rawValue, userInfo: userInfo)
  }

  /// A failure attributed to the test process rather than to idb, in `TestFailureErrorDomain`.
  public static func testFailure(_ description: String) -> NSError {
    NSError(domain: TestFailureErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: description])
  }
}
