/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import Testing

@Suite
struct FBDeviceControlFrameworkLoaderTests {

  init() {
    if ProcessInfo.processInfo.environment[FBControlCoreStderrLogging] == nil {
      setenv(FBControlCoreStderrLogging, "YES", 1)
    }
    if ProcessInfo.processInfo.environment[FBControlCoreDebugLogging] == nil {
      setenv(FBControlCoreDebugLogging, "NO", 1)
    }
  }

  @Test
  func constructsDeviceSet() throws {
    let deviceSet = try FBDeviceSet(logger: FBControlCoreGlobalConfiguration.defaultLogger, delegate: nil, ecidFilter: nil)
    #expect((deviceSet) != nil)
    #expect((deviceSet.allDevices) != nil)
  }
}
