/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorCodeInjection
import Testing

private typealias Reader = SimulatorAudioInjectionCommands.LaunchdEnvironmentReader

@Suite struct LaunchdEnvironmentReaderTests {

  @Test func launchesReadLaunchdWithLaunchctlUnlessTheCompanionOptsIn() {
    #expect(Reader.selected(by: [:]) == .launchctl)
    #expect(Reader.selected(by: ["IDB_LAUNCHD_GETENV": "launchctl"]) == .launchctl)
  }

  @Test func theCompanionOptsIntoCoreSimulatorByName() {
    #expect(Reader.selected(by: ["IDB_LAUNCHD_GETENV": "coresimulator"]) == .coreSimulator)
  }

  @Test(arguments: ["", "CoreSimulator", "1", "true"])
  func anyOtherValueKeepsLaunchctl(value: String) {
    #expect(Reader.selected(by: ["IDB_LAUNCHD_GETENV": value]) == .launchctl)
  }
}
