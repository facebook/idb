/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Covers what a log tail backed by a process reports to its waiter: success
/// only on a zero exit, and termination of the process when the wait is
/// cancelled, escalating to SIGKILL for a process that ignores SIGTERM.
@Suite(.serialized)
struct ProcessLogOperationTests {

  private static func operation(_ script: String) async throws -> (ProcessLogOperation, pid_t) {
    let process = try await Subprocess(executable: "/bin/sh", arguments: ["-c", script])
      .launch(output: .nullDevice, error: .nullDevice)
    let operation = ProcessLogOperation(process: process, executable: "/bin/sh", consumer: FBDataBuffer.accumulatingBuffer())
    return (operation, process.processIdentifier)
  }

  private static func isAlive(_ processIdentifier: pid_t) -> Bool {
    kill(processIdentifier, 0) == 0
  }

  private static func waitUntilDead(_ processIdentifier: pid_t, within seconds: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if !isAlive(processIdentifier) {
        return true
      }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return false
  }

  @Test("The wait completes when the process exits zero")
  func zeroExitCompletes() async throws {
    let (operation, _) = try await Self.operation("exit 0")

    try await operation.waitUntilCompleted()
  }

  @Test("The wait fails when the process exits non-zero")
  func nonZeroExitFails() async throws {
    let (operation, _) = try await Self.operation("exit 3")

    await #expect(throws: (any Error).self) {
      try await operation.waitUntilCompleted()
    }
  }

  @Test("Cancelling the wait terminates the process")
  func cancellationTerminatesTheProcess() async throws {
    let (operation, processIdentifier) = try await Self.operation("sleep 10000")

    let waiting = Task { try await operation.waitUntilCompleted() }
    waiting.cancel()

    await #expect(throws: (any Error).self) {
      try await waiting.value
    }
    #expect(await Self.waitUntilDead(processIdentifier, within: 15))
  }

  @Test("Cancelling the wait kills a process that ignores SIGTERM once the grace period passes")
  func cancellationEscalatesToKill() async throws {
    let (operation, processIdentifier) = try await Self.operation("trap '' TERM; echo ready; sleep 10000")
    // Give the shell time to install the trap before the SIGTERM arrives.
    try await Task.sleep(for: .milliseconds(500))

    let waiting = Task { try await operation.waitUntilCompleted() }
    waiting.cancel()
    _ = try? await waiting.value

    #expect(await Self.waitUntilDead(processIdentifier, within: 20))
  }

  @Test(
    "os_log arguments gain a leading stream unless they already name a subcommand",
    arguments: [
      ([], ["stream"]),
      (["show", "--last", "1m"], ["show", "--last", "1m"]),
      (["collect"], ["collect"]),
      (["--level", "debug"], ["stream", "--level", "debug"]),
    ] as [([String], [String])])
  func streamIsInsertedUnlessASubcommandIsNamed(arguments: [String], expected: [String]) {
    #expect(ProcessLogOperation.osLogArgumentsInsertStreamIfNeeded(arguments) == expected)
  }
}
