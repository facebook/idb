/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Pins what cancelling a process future does to the process behind it.
///
/// `FBProcessBuilder.h` says of `runUntilCompletionWithAcceptableExitCodes:` that
/// "Cancelling the process will cancel the task", while `FBSubprocess.h` says of
/// each termination future that "Cancelling this Future will have no effect". These
/// cases establish which of the two describes what actually happens.
///
/// Nothing here asserts a desirable design. Each case records what callers observe
/// today so that a later replacement has to either reproduce it or change it
/// deliberately.
@Suite
struct FBSubprocessCancellationTests {

  /// Bounds every poll: generous enough for a loaded machine, small enough that a
  /// wedged child fails the case in seconds rather than minutes.
  private static let pollingDeadlineSeconds = 15

  /// A `/bin/sh` fragment that blocks until the file at `path` exists.
  ///
  /// The children gate on a file the test creates only after it has issued the
  /// cancellation, rather than sleeping for a fixed interval. The window in which
  /// the child is alive therefore cannot close early, however loaded or suspended
  /// the machine — each case's assertions run while the gate is still shut.
  private static func shellWait(forFileAtPath path: String) -> String {
    "while [ ! -e '\(path)' ]; do sleep 0.05; done"
  }

  private static func waitUntil(seconds: Int = pollingDeadlineSeconds, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(TimeInterval(seconds))
    while Date() < deadline {
      if condition() {
        return true
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
  }

  private static func waitForFile(atPath path: String) async -> Bool {
    await waitUntil { FileManager.default.fileExists(atPath: path) }
  }

  @Test("Cancelling a runUntilCompletion future abandons the observation and leaves the process running")
  func cancellingRunUntilCompletionDoesNotStopTheProcess() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FBSubprocessCancellationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let started = directory.appendingPathComponent("started").path
    let gate = directory.appendingPathComponent("gate").path
    let finished = directory.appendingPathComponent("finished").path

    // The child installs no signal handlers, and can only reach the second marker
    // by passing the gate, which is created after the cancellation below. A child
    // terminated by that cancellation could therefore never produce `finished`.
    let future = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/bin/sh", arguments: ["-c", "/usr/bin/touch '\(started)'; \(Self.shellWait(forFileAtPath: gate)); /usr/bin/touch '\(finished)'"])
      .runUntilCompletion(withAcceptableExitCodes: nil)

    #expect(await Self.waitForFile(atPath: started), "The child never launched")
    try await bridgeFBFutureVoid(future.cancel())

    // The gate is still shut, so the child cannot have exited: the states below are
    // those of a future whose process is still running.
    #expect(future.state == .cancelled)
    #expect(future.error == nil, "Cancellation is a state of its own, not an error result")
    await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(future)
    }

    // The caller has stopped watching; the process has not stopped working. Opening
    // the gate lets it run to completion, and nothing in the tree will ever read its
    // exit status.
    #expect(FileManager.default.createFile(atPath: gate, contents: nil))
    #expect(await Self.waitForFile(atPath: finished), "The child was terminated by the cancellation")
  }

  @Test("Cancelling exitCode loses the exit code for good, while statLoc still resolves")
  func cancellingExitCodeLosesTheCodeButNotTheTermination() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FBSubprocessCancellationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let started = directory.appendingPathComponent("started").path
    let gate = directory.appendingPathComponent("gate").path

    let process = try await bridgeFBFuture(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/sh", arguments: ["-c", "/usr/bin/touch '\(started)'; \(Self.shellWait(forFileAtPath: gate)); exit 7"])
        .start())

    // Cancelling an already-resolved future is a no-op, so the cancellation must be
    // issued while the child is still alive for this case to pin anything. The
    // marker proves the child is running and the shut gate keeps it that way.
    #expect(await Self.waitForFile(atPath: started), "The child never launched")

    let exitCode = process.exitCode
    try await bridgeFBFutureVoid(exitCode.cancel())

    // Asserted before the gate opens, while the child provably cannot have exited.
    #expect(exitCode.state == .cancelled)
    #expect(exitCode.result == nil)

    // "No effect" is about the process, not about the future: the process is left
    // alone and `statLoc` reports its end as usual, while the cancelled future never
    // delivers the code it was going to carry.
    #expect(FileManager.default.createFile(atPath: gate, contents: nil))
    #expect(try await bridgeFBFuture(process.statLoc).intValue == 7 << 8)
  }

  // MARK: - Stranded children

  @Test("A child waiting on a gate keeps polling after the gate's directory is removed")
  func aGateWaitWhoseDirectoryIsRemoved() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FBSubprocessCancellationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let started = directory.appendingPathComponent("started").path
    let gate = directory.appendingPathComponent("gate").path

    let process = try await bridgeFBFuture(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/sh", arguments: ["-c", "/usr/bin/touch '\(started)'; \(Self.shellWait(forFileAtPath: gate))"])
        .start())
    defer { _ = process.sendSignal(SIGKILL) }
    #expect(await Self.waitForFile(atPath: started), "The child never launched")

    // What each case's `defer` does when a thrown error skips the line that opens the gate.
    try FileManager.default.removeItem(at: directory)

    // BUG: the gate can never open, yet the child polls for it indefinitely — flipped in the following commit.
    #expect(await Self.waitUntil(seconds: 1) { process.statLoc.state != .running } == false)
  }

  @Test("A child waiting on a gate keeps polling after the process that started it has gone")
  func aGateWaitWhoseParentHasGone() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FBSubprocessCancellationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = directory.appendingPathComponent("gate").path

    // The outer shell backgrounds the waiter and exits at once, orphaning it as a killed test runner would.
    let launcher = try await bridgeFBFuture(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/sh", arguments: ["-c", "/bin/sh -c \"$1\" </dev/null >/dev/null 2>&1 & echo $!", "sh", Self.shellWait(forFileAtPath: gate)])
        .withStdOutInMemoryAsString()
        .runUntilCompletion(withAcceptableExitCodes: nil))
    let pid = try #require(pid_t(((launcher.stdOut as String?) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { kill(pid, SIGKILL) }

    // BUG: nothing will ever open the gate, yet the orphan polls for it indefinitely — flipped in the following commit.
    #expect(await Self.waitUntil(seconds: 1) { kill(pid, 0) != 0 } == false)
  }
}
