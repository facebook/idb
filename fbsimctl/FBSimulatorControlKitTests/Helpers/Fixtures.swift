/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import XCTest
import FBSimulatorControl
@testable import FBSimulatorControlKit

public struct Fixtures {
  static func application() -> FBSimulatorApplication {
    return FBSimulatorApplication.xcodeSimulator()
  }

  static func binary() -> FBSimulatorBinary {
    let basePath: NSString = FBControlCoreGlobalConfiguration.developerDirectory()
    return try! FBSimulatorBinary(
      path: basePath.stringByAppendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/sbin/launchd_sim")
    )
  }
}
