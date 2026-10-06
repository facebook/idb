/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A running REPL session. The host has injected the REPL shim, which binds the
/// control socket at `socketPath` and serves `dlopen`/`dlsym`/call requests.
public struct LaunchedRepl: Sendable {

  /// What hosts the REPL, and so what ending the session waits for.
  public enum Host: Sendable {
    /// A process of its own, which exits once the control socket is closed.
    case process(RunningSubprocess)
    /// A logic test run executing the shim's `TestRepl/start`, which finishes once
    /// the control socket is closed.
    case testRun(Task<Void, any Error>)
    /// An app, which outlives the session and resets for the next client.
    case app
  }

  public let socketPath: String
  public let host: Host
  /// Paths to pre-built `.swiftinterface` files (the `IDB` module's) that the
  /// companion reports to the driver alongside any the host generates, so injected
  /// code can `import` them. The matching code is loaded into the REPL host.
  public let extraInterfacePaths: [String]

  public init(socketPath: String, host: Host, extraInterfacePaths: [String] = []) {
    self.socketPath = socketPath
    self.host = host
    self.extraInterfacePaths = extraInterfacePaths
  }

  /// Waits for the host to finish once the control socket is closed; returns
  /// immediately for an app. Cancelling the wait cancels a test run.
  public func waitForHostToFinish() async throws {
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
