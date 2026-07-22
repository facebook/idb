/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import Foundation
import XCTest

final class ProcessExitWaitTests: XCTestCase {

  /// A process that has already exited (and been reaped) never delivers a `.exit`
  /// event, so `waitForProcessExit` must resolve via its liveness fallback rather
  /// than hang. This is the race the app-exit recording cleanup depends on.
  func testResolvesForAnAlreadyExitedProcess() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/echo")
    process.arguments = ["idb-repl-process-exit-test"]
    try process.run()
    process.waitUntilExit()

    await waitForProcessExit(pid: process.processIdentifier)
  }

  /// A live process that exits while being watched resolves the wait (and the
  /// `DispatchSource` survives long enough to deliver the event).
  func testResolvesWhenAWatchedProcessExits() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["0.3"]
    try process.run()

    await waitForProcessExit(pid: process.processIdentifier)
    XCTAssertFalse(process.isRunning)
  }
}
