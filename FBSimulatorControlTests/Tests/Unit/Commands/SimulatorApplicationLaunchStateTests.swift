/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing

private struct NotRunning: Error {}

/// What a launch-state check asked of the simulator.
private final class AppState {
  let runningProcessIdentifier: pid_t?
  private(set) var lookups = 0
  private(set) var kills = 0

  init(running runningProcessIdentifier: pid_t?) {
    self.runningProcessIdentifier = runningProcessIdentifier
  }

  func confirm(_ launchMode: ApplicationLaunchMode, waitForDebugger: Bool = false) async throws {
    try await SimulatorApplicationCommands.confirmApplicationLaunchState(
      bundleID: "com.example.app",
      launchMode: launchMode,
      waitForDebugger: waitForDebugger,
      runningProcessIdentifier: {
        self.lookups += 1
        guard let pid = self.runningProcessIdentifier else {
          throw NotRunning()
        }
        return pid
      },
      kill: { self.kills += 1 })
  }
}

@Suite
struct SimulatorApplicationLaunchStateTests {

  @Test(arguments: [pid_t?.some(42), nil])
  func aLaunchThatForegroundsARunningAppNeverAsksWhetherItIsRunning(running: pid_t?) async throws {
    let app = AppState(running: running)

    try await app.confirm(.foregroundIfRunning)

    #expect(app.lookups == 0)
    #expect(app.kills == 0)
  }

  @Test
  func foregroundingARunningAppCannotWaitForADebugger() async throws {
    let app = AppState(running: 42)

    await #expect(throws: SimulatorApplicationLaunchError.self) {
      try await app.confirm(.foregroundIfRunning, waitForDebugger: true)
    }
    #expect(app.lookups == 0)
  }

  @Test
  func aLaunchThatMustFindTheAppStoppedIsRefusedWhenItIsRunning() async throws {
    let app = AppState(running: 42)

    do {
      try await app.confirm(.failIfRunning)
      Issue.record("a running app was not refused")
    } catch SimulatorApplicationLaunchError.applicationAlreadyRunning(let bundleID, let processIdentifier) {
      #expect(bundleID == "com.example.app")
      #expect(processIdentifier == 42)
    }
    #expect(app.kills == 0)
  }

  @Test(arguments: [ApplicationLaunchMode.failIfRunning, .relaunchIfRunning])
  func anAppThatIsNotRunningIsLaunchedAsItIs(mode: ApplicationLaunchMode) async throws {
    let app = AppState(running: nil)

    try await app.confirm(mode)

    #expect(app.lookups == 1)
    #expect(app.kills == 0)
  }

  @Test
  func aRelaunchKillsTheRunningApp() async throws {
    let app = AppState(running: 42)

    try await app.confirm(.relaunchIfRunning)

    #expect(app.lookups == 1)
    #expect(app.kills == 1)
  }
}
