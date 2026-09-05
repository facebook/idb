/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Pins how a finished `FBSubprocess` reports the way it ended.
///
/// Termination is spread across three futures — `statLoc`, `exitCode` and
/// `signal` — of which exactly one of the latter two resolves with a result and
/// the other always resolves with an *error*. These cases record the exact
/// states, the numeric values, and the error text, because callers branch on all
/// three and at least one out-of-repo consumer string-matches the messages.
@Suite
struct FBSubprocessTerminationTests {

  private typealias Subprocess = FBSubprocess<NSNull, NSString, NSData>

  private static func start(_ script: String) async throws -> Subprocess {
    try await bridgeFBFuture(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/sh", arguments: ["-c", script])
        .withStdOutInMemoryAsString()
        .start())
  }

  // MARK: - Normal exit

  @Test("A normal exit resolves statLoc and exitCode, and fails signal with a message naming the code")
  func normalExitFailsTheSignalFuture() async throws {
    let process = try await Self.start("exit 0")

    // All three futures resolve from one block, so once `exitCode` is awaited the other two are settled.
    #expect(try await bridgeFBFuture(process.exitCode).int32Value == 0)
    #expect(process.statLoc.result?.int32Value == 0)

    let error = await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(process.signal)
    }
    #expect(error?.localizedDescription.contains("exited with code 0") == true)
  }

  @Test(
    "A non-zero exit is carried in the high byte of statLoc",
    arguments: [Int32(1), Int32(3), Int32(149), Int32(255)])
  func exitCodeOccupiesTheHighByteOfStatLoc(code: Int32) async throws {
    let process = try await Self.start("exit \(code)")

    #expect(try await bridgeFBFuture(process.exitCode).int32Value == code)

    // `statLoc` is the raw wait(2) status word, not a normalised code. The
    // decode in `FBProcessSpawnCommandHelpers` is `(statLoc >> 8) & 0xff`.
    #expect(process.statLoc.result?.int32Value == code << 8)
  }

  // MARK: - Death by signal

  @Test(
    "A process that dies of a signal resolves statLoc and signal, and fails exitCode",
    arguments: [SIGTERM, SIGKILL, SIGINT])
  func signalledProcessFailsTheExitCodeFuture(signo: Int32) async throws {
    let process = try await Self.start("kill -\(signo) $$")

    #expect(try await bridgeFBFuture(process.signal).int32Value == signo)

    // For death by signal the low seven bits of the wait status hold the signal
    // number and the high byte is zero, so there is no exit code to read.
    #expect(process.statLoc.result?.int32Value == signo)

    let error = await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(process.exitCode)
    }
    #expect(error?.localizedDescription.contains("exited with signal \(signo)") == true)
  }

  @Test("A signal sent through sendSignal is reported identically to a self-inflicted one")
  func sentSignalIsIndistinguishableFromASelfInflictedOne() async throws {
    let process = try await Self.start("sleep 10000")

    #expect(try await bridgeFBFuture(process.sendSignal(SIGKILL)).int32Value == SIGKILL)
    #expect(try await bridgeFBFuture(process.signal).int32Value == SIGKILL)
    #expect(process.statLoc.result?.int32Value == SIGKILL)

    await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(process.exitCode)
    }
  }

  // MARK: - How the triple reaches runUntilCompletion callers

  @Test("runUntilCompletion rejects a signalled process even when no exit code is unacceptable")
  func runUntilCompletionRejectsASignalledProcessWithNilAcceptableCodes() async throws {
    // `nil` acceptable codes reads as "accept any outcome", and does mean that
    // for a process that exits. But `-exitedWithCodes:` chains off `exitCode`,
    // which resolves with an *error* when the process was signalled, so the
    // whole call fails before any exit code is inspected.
    let error = await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(
        FBProcessBuilder<NSNull, NSData, NSData>
          .withLaunchPath("/bin/sh", arguments: ["-c", "kill -9 $$"])
          .runUntilCompletion(withAcceptableExitCodes: nil))
    }
    #expect(error?.localizedDescription.contains("exited with signal \(SIGKILL)") == true)
  }

  @Test("An unacceptable exit code fails with a message that out-of-repo tooling matches on")
  func unacceptableExitCodeErrorTextIsPartOfTheContract() async throws {
    let error = await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(
        FBProcessBuilder<NSNull, NSData, NSData>
          .withLaunchPath("/bin/sh", arguments: ["-c", "exit 149"])
          .runUntilCompletion(withAcceptableExitCodes: [0]))
    }

    // @oss-disable
    #expect(error?.localizedDescription.contains("Exit Code 149 is not acceptable") == true)
  }

  // MARK: - Ordering against IO teardown

  @Test("Termination is not observable until output has finished draining")
  func terminationResolvesOnlyAfterTheOutputDrainCompletes() async throws {
    // `statLoc` is resolved inside the completion of the IO attachment's
    // teardown, so the earliest moment a caller can see the process end is
    // already after the last byte of output has been consumed.
    let process = try await Self.start("/usr/bin/seq 1 200000")
    _ = try await bridgeFBFuture(process.statLoc)

    let stdOut = try #require(process.stdOut) as String
    #expect(stdOut.hasSuffix("200000"))
    #expect(stdOut.components(separatedBy: "\n").count == 200_000)
  }
}
