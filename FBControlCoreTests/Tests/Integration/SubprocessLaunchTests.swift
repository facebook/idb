/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Covers the escaping and scoped lifetimes of `Subprocess`: what a
/// `launch()` handle reports and permits, and that `withRunning` owns its
/// process — the child is dead once the scope exits, however it exits.
///
/// Serialized for the same reason as `SubprocessRunTests`: concurrent
/// spawning under suite load produces transient launch failures.
@Suite(.serialized)
struct SubprocessLaunchTests {

  private static func shell(_ script: String) -> Subprocess {
    Subprocess(executable: "/bin/sh", arguments: ["-c", script])
  }

  private static func isAlive(_ processIdentifier: pid_t) -> Bool {
    kill(processIdentifier, 0) == 0
  }

  // MARK: - The escaping handle

  @Test("A natural exit is reported to the handle")
  func naturalExitReachesTheHandle() async throws {
    let running = try await Self.shell("exit 3").launch(output: .closed, error: .closed)

    #expect(running.processIdentifier > 0)
    #expect(try await running.terminationStatus == .exited(3))
  }

  @Test("A signalled process reports the signal, and every waiter sees it")
  func signalReachesEveryWaiter() async throws {
    let running = try await Self.shell("sleep 10000").launch(output: .closed, error: .closed)

    async let first = running.terminationStatus
    async let second = running.terminationStatus
    running.sendSignal(SIGTERM)

    #expect(try await first == .signalled(SIGTERM))
    #expect(try await second == .signalled(SIGTERM))
  }

  @Test("Sending a signal after termination is a no-op")
  func signalAfterExitIsANoOp() async throws {
    let running = try await Self.shell("exit 0").launch(output: .closed, error: .closed)
    #expect(try await running.terminationStatus == .exited(0))

    // The engine skips the kill once terminated, so a recycled pid can never
    // be signalled by a stale handle.
    running.sendSignal(SIGKILL)
    #expect(try await running.terminationStatus == .exited(0))
  }

  @Test("Terminating a process that ignores SIGTERM escalates to SIGKILL after the grace period")
  func terminationEscalatesToSigkill() async throws {
    let running = try await Self.shell("trap '' TERM; sleep 10000").launch(output: .closed, error: .closed)
    // The trap is installed by the time output arrives, so give the shell a
    // moment to reach it rather than racing the launch.
    try await Task.sleep(for: .milliseconds(200))

    let status = try await running.terminate(gracePeriod: 0.5)

    #expect(status == .signalled(SIGKILL))
  }

  @Test("Termination is observable only after output has drained")
  func terminationWaitsForTheDrain() async throws {
    final class Collected: @unchecked Sendable {
      private let lock = NSLock()
      private var lines: [String] = []
      func append(_ line: String) { lock.withLock { lines.append(line) } }
      var snapshot: [String] { lock.withLock { lines } }
    }
    let lines = Collected()
    let running = try await Self.shell("/usr/bin/seq 1 20000").launch(output: .lines { lines.append($0) }, error: .closed)

    _ = try await running.terminationStatus
    // The line consumer delivers asynchronously; poll for the tail.
    for _ in 0..<200 where lines.snapshot.count < 20000 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(lines.snapshot.count == 20000)
    #expect(lines.snapshot.last == "20000")
  }

  // MARK: - The scoped lifetime

  @Test("withRunning terminates the process when the body returns")
  func scopeExitTerminatesTheProcess() async throws {
    let processIdentifier = try await Self.shell("sleep 10000").withRunning(output: .closed, error: .closed) { running in
      #expect(Self.isAlive(running.processIdentifier))
      return running.processIdentifier
    }

    #expect(!Self.isAlive(processIdentifier))
  }

  @Test("withRunning terminates the process when the body throws")
  func bodyErrorStillTerminatesTheProcess() async throws {
    struct BodyError: Error {}
    var processIdentifier: pid_t = 0

    await #expect(throws: BodyError.self) {
      try await Self.shell("sleep 10000").withRunning(output: .closed, error: .closed) { running in
        processIdentifier = running.processIdentifier
        throw BodyError()
      }
    }

    #expect(processIdentifier > 0)
    #expect(!Self.isAlive(processIdentifier))
  }

  @Test("withRunning terminates the process when the surrounding task is cancelled")
  func cancellationStillTerminatesTheProcess() async throws {
    final class Box: @unchecked Sendable {
      private let lock = NSLock()
      private var value: pid_t = 0
      func set(_ pid: pid_t) { lock.withLock { value = pid } }
      var pid: pid_t { lock.withLock { value } }
    }
    let box = Box()

    let task = Task {
      try await Self.shell("sleep 10000").withRunning(output: .closed, error: .closed) { running in
        box.set(running.processIdentifier)
        try await Task.sleep(for: .seconds(100))
      }
    }
    for _ in 0..<200 where box.pid == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let processIdentifier = box.pid
    try #require(processIdentifier > 0)
    #expect(Self.isAlive(processIdentifier))

    task.cancel()
    _ = try? await task.value

    #expect(!Self.isAlive(processIdentifier))
  }

  @Test("The body sees live output while the process runs")
  func bodyObservesLiveOutput() async throws {
    final class Flag: @unchecked Sendable {
      private let lock = NSLock()
      private var raised = false
      func raise() { lock.withLock { raised = true } }
      var isRaised: Bool { lock.withLock { raised } }
    }
    let ready = Flag()

    try await Self.shell("printf 'ready\\n'; sleep 10000").withRunning(
      output: .lines { line in
        if line == "ready" {
          ready.raise()
        }
      },
      error: .closed
    ) { running in
      for _ in 0..<200 where !ready.isRaised {
        try await Task.sleep(nanoseconds: 10_000_000)
      }
      // The line arrived while the process is still alive: streaming is
      // live, not an at-exit capture.
      #expect(ready.isRaised)
      #expect(Self.isAlive(running.processIdentifier))
    }
  }
}
