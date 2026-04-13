/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import XCTest

final class FBDeviceControlFrameworkLoaderTests: XCTestCase {

  override class func setUp() {
    super.setUp()
    if ProcessInfo.processInfo.environment[FBControlCoreStderrLogging] == nil {
      setenv(FBControlCoreStderrLogging, "YES", 1)
    }
    if ProcessInfo.processInfo.environment[FBControlCoreDebugLogging] == nil {
      setenv(FBControlCoreDebugLogging, "NO", 1)
    }
  }

  func testConstructsDeviceSet() throws {
    let deviceSet = try FBDeviceSet(logger: FBControlCoreGlobalConfiguration.defaultLogger, delegate: nil, ecidFilter: nil)
    XCTAssertNotNil(deviceSet)
    XCTAssertNotNil(deviceSet.allDevices)
  }
}
