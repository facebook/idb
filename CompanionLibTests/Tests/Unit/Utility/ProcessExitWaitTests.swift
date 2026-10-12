/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import Foundation
import Testing

@Suite
struct ProcessExitWaitTests {

  /// A process that has already exited (and been reaped) never delivers a `.exit`
  /// event, so `waitForProcessExit` must resolve via its liveness fallback rather
  /// than hang. This is the race the app-exit recording cleanup depends on.
  @Test
  func resolvesForAnAlreadyExitedProcess() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/echo")
    process.arguments = ["idb-repl-process-exit-test"]
    try process.run()
    process.waitUntilExit()

    await waitForProcessExit(pid: process.processIdentifier)
  }

  /// A live process that exits while being watched resolves the wait (and the
  /// `DispatchSource` survives long enough to deliver the event), and not before it
  /// exits: `sleep 0.3` cannot exit sooner than 300 ms after it is launched.
  ///
  /// `Process.isRunning` is no measure of that: `Process` learns of the exit from a
  /// source of its own, which may run after the one that resolves the wait.
  @Test
  func resolvesWhenAWatchedProcessExits() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["0.3"]
    let launched = ContinuousClock.now
    try process.run()

    await waitForProcessExit(pid: process.processIdentifier)
    #expect(ContinuousClock.now - launched >= .milliseconds(300))
  }
}
