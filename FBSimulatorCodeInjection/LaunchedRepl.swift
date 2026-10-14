/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// A running REPL session. The host has injected the REPL shim, which binds the
/// control socket at `socketPath` and serves `dlopen`/`dlsym`/call requests.
struct LaunchedRepl: Sendable {

  /// What hosts the REPL, and so what ending the session waits for.
  enum Host: Sendable {
    /// A process of its own, which exits once the control socket is closed.
    case process(RunningSubprocess)
    /// A logic test run executing the shim's `TestRepl/start`, which finishes once
    /// the control socket is closed.
    case testRun(Task<Void, any Error>)
    /// An app, which outlives the session and resets for the next client.
    case app
  }

  let socketPath: String
  let host: Host

  /// Waits for the host to finish once the control socket is closed; returns
  /// immediately for an app. Cancelling the wait cancels a test run.
  func waitForHostToFinish() async throws {
    switch host {
    case let .process(process):
      _ = try await process.terminationStatus
    case let .testRun(run):
      try await withTaskCancellationHandler {
        try await run.value
      } onCancel: {
        run.cancel()
      }
    case .app:
      return
    }
  }
}
