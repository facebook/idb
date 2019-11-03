/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
@testable import FBSimulatorControlKit
import XCTest

public struct Fixtures {
  static func application() -> FBSimulatorApplication {
    return FBSimulatorApplication.xcodeSimulator()
  }

  static func binary() -> FBSimulatorBinary {
    let basePath: NSString = FBXcodeConfiguration.developerDirectory()
    return try! FBSimulatorBinary(
      path: basePath.stringByAppendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/sbin/launchd_sim")
    )
  }
}
