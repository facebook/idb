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

  @Test func launchesReadLaunchdThroughCoreSimulatorUnlessTheCompanionOptsOut() {
    #expect(Reader.selected(by: [:]) == .coreSimulator)
    #expect(Reader.selected(by: ["IDB_LAUNCHD_GETENV": "coresimulator"]) == .coreSimulator)
  }

  @Test func theCompanionSelectsLaunchctlByName() {
    #expect(Reader.selected(by: ["IDB_LAUNCHD_GETENV": "launchctl"]) == .launchctl)
  }

  @Test(arguments: ["", "Launchctl", "0", "false"])
  func anyOtherValueKeepsCoreSimulator(value: String) {
    #expect(Reader.selected(by: ["IDB_LAUNCHD_GETENV": value]) == .coreSimulator)
  }
}
