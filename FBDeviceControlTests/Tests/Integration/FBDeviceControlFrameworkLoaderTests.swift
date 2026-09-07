/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
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
    let devices = deviceSet.allDevices
    #expect(devices.allSatisfy { !$0.udid.isEmpty })
    #expect(Set(devices.map(\.udid)).count == devices.count)
  }
}
