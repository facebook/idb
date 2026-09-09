/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Differential coverage for `Subprocess.run`: every scenario is executed
/// through both the `FBProcessBuilder` path and the `Subprocess` path, and
/// the observable outcomes — captured output, termination, acceptability —
/// must be identical. This is what makes the façade's "no behaviour change"
/// checkable rather than asserted.
///
/// Serialized: each test spawns two child processes, and running them all
/// concurrently under suite load produces transient launch failures that
/// read as differential mismatches.
@Suite(.serialized)
struct SubprocessRunTests {

  private static func old(_ script: String) -> FBProcessBuilder<NSNull, NSData, NSData> {
    FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/bin/sh", arguments: ["-c", script])
  }

  private static func new(_ script: String) -> Subprocess {
    Subprocess(executable: "/bin/sh", arguments: ["-c", script])
  }

  // MARK: - Captures

  @Test("A string capture returns the same stdout as the in-memory string sink")
  func stringCaptureMatchesTheStringSink() async throws {
    let old = try await bridgeFBFuture(
      Self.old("printf 'out'").withStdOutInMemoryAsString().runUntilCompletion(withAcceptableExitCodes: [0]))
    let new = try await Self.new("printf 'out'").run(output: .string, error: .closed)

    #expect(new.standardOutput == "out")
    #expect(new.standardOutput == (old.stdOut as? String))
    #expect(new.terminationStatus == .exited(old.exitCode.result?.int32Value ?? -1))
  }

  @Test("A stderr capture returns the same bytes as the in-memory sink")
  func stderrCaptureMatchesTheStringSink() async throws {
    let old = try await bridgeFBFuture(
      Self.old("printf 'err' 1>&2").withStdErrInMemoryAsString().runUntilCompletion(withAcceptableExitCodes: [0]))
    let new = try await Self.new("printf 'err' 1>&2").run(output: .closed, error: .string)

    #expect(new.standardError == "err")
    #expect(new.standardError == (old.stdErr as? String))
  }

  @Test("A data capture returns the same bytes as the in-memory data sink")
  func dataCaptureMatchesTheDataSink() async throws {
    let old = try await bridgeFBFuture(
      Self.old("printf 'bytes'").withStdOutInMemoryAsData().runUntilCompletion(withAcceptableExitCodes: [0]))
    let new = try await Self.new("printf 'bytes'").run(output: .data, error: .closed)

    #expect(new.standardOutput == Data("bytes".utf8))
    #expect(new.standardOutput == (old.stdOut as? Data))
  }

  @Test("A file capture writes the same contents as the file-path sink")
  func fileCaptureMatchesTheFilePathSink() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SubprocessRunTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let oldPath = directory.appendingPathComponent("old.txt")
    let newPath = directory.appendingPathComponent("new.txt")
    // The engine opens file sinks with O_CREAT and no mode, so a file it
    // creates itself has undefined permissions and may not be readable back.
    #expect(FileManager.default.createFile(atPath: oldPath.path, contents: nil))
    #expect(FileManager.default.createFile(atPath: newPath.path, contents: nil))

    _ = try await bridgeFBFuture(
      Self.old("/usr/bin/seq 1 100").withStdOutPath(oldPath.path).runUntilCompletion(withAcceptableExitCodes: [0]))
    let new = try await Self.new("/usr/bin/seq 1 100").run(output: .file(newPath), error: .closed)

    #expect(new.standardOutput == newPath)
    #expect(try String(contentsOf: newPath, encoding: .utf8) == (try String(contentsOf: oldPath, encoding: .utf8)))
  }

  @Test("A line sink receives the same lines as the builder's line reader")
  func lineSinkMatchesTheLineReader() async throws {
    // SAFETY: `lines` is the only mutable state and every read and write of it
    // goes through `lock`; the line sinks call in from arbitrary queues.
    // patternlint-disable-next-line unchecked-sendable
    final class Collected: @unchecked Sendable {
      private let lock = NSLock()
      private var lines: [String] = []
      func append(_ line: String) { lock.withLock { lines.append(line) } }
      var snapshot: [String] { lock.withLock { lines } }
    }
    let oldLines = Collected()
    let newLines = Collected()

    _ = try await bridgeFBFuture(
      Self.old("printf 'a\\nb\\nc\\n'")
        .withStdOutLineReader { oldLines.append($0) }
        .runUntilCompletion(withAcceptableExitCodes: [0]))
    _ = try await Self.new("printf 'a\\nb\\nc\\n'").run(output: .lines { newLines.append($0) }, error: .closed)

    // Both paths deliver lines through the asynchronous block consumer, so
    // delivery can trail termination; poll rather than assert immediately.
    for _ in 0..<100 where newLines.snapshot.count < 3 || oldLines.snapshot.count < 3 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(newLines.snapshot == ["a", "b", "c"])
    #expect(newLines.snapshot == oldLines.snapshot)
  }

  @Test("An unconfigured run captures both streams as strings, the builder's unset default made visible")
  func unconfiguredRunMatchesTheBuilderDefaults() async throws {
    let old = try await bridgeFBFuture(
      Self.old("printf 'out'; printf 'err' 1>&2").runUntilCompletion(withAcceptableExitCodes: [0]))
    let new = try await Self.new("printf 'out'; printf 'err' 1>&2").run()

    #expect(new.standardOutput == (old.stdOut as? String))
    #expect(new.standardError == (old.stdErr as? String))
    #expect(new.terminationStatus == .exited(0))
  }

  // MARK: - Environment

  @Test("An exact environment produces the same child environment as the builder's")
  func exactEnvironmentMatchesTheBuilder() async throws {
    let old = try await bridgeFBFuture(
      Self.old("/usr/bin/env")
        .withEnvironment(["FOO": "BAR"])
        .withStdOutInMemoryAsString()
        .runUntilCompletion(withAcceptableExitCodes: [0]))
    var spec = Self.new("/usr/bin/env")
    spec.environment = .exact(["FOO": "BAR"])
    let new = try await spec.run(output: .string, error: .closed)

    #expect(new.standardOutput.contains("FOO=BAR"))
    #expect(new.standardOutput == (old.stdOut as? String))
  }

  // MARK: - The two dev nulls

  @Test("A closed output leaves the child's descriptor closed, exactly like the builder's dev-null")
  func closedOutputMatchesTheBuilderDevNull() async throws {
    // `/dev/fd/1` exists only while fd 1 is open in the child, so `test -e`
    // discriminates a closed descriptor (exit 1) from any open sink (exit 0).
    let old = try await bridgeFBFuture(
      Self.old("test -e /dev/fd/1").withStdOutToDevNull().runUntilCompletion(withAcceptableExitCodes: nil))
    let new = try await Self.new("test -e /dev/fd/1").run(output: .closed, error: .closed, exitPolicy: .any)

    #expect(new.terminationStatus == .exited(1))
    #expect(new.terminationStatus == .exited(old.exitCode.result?.int32Value ?? -1))
  }

  @Test("A null-device output hands the child an open descriptor, which nothing on the old host path could")
  func nullDeviceOutputIsOpenOnTheHost() async throws {
    let new = try await Self.new("test -e /dev/fd/1").run(output: .nullDevice, error: .closed, exitPolicy: .any)

    #expect(new.terminationStatus == .exited(0))
  }

  // MARK: - Termination parity

  @Test(
    "Any-policy runs report the exit code the old nil-codes path reports",
    arguments: [Int32(0), Int32(3), Int32(149)])
  func exitCodesMatchTheNilCodesPath(code: Int32) async throws {
    let old = try await bridgeFBFuture(
      Self.old("exit \(code)").runUntilCompletion(withAcceptableExitCodes: nil))
    let new = try await Self.new("exit \(code)").run(output: .closed, error: .closed, exitPolicy: .any)

    #expect(new.terminationStatus == .exited(code))
    #expect(new.terminationStatus == .exited(old.exitCode.result?.int32Value ?? -1))
  }

  @Test("A signalled process reports the signal the old signal future reports")
  func signalsMatchTheSignalFuture() async throws {
    let old = try await bridgeFBFuture(Self.old("kill -TERM $$").start())
    let oldSignal = try await bridgeFBFuture(old.signal).int32Value
    let new = try await Self.new("kill -TERM $$").run(output: .closed, error: .closed, exitPolicy: .any)

    #expect(new.terminationStatus == .signalled(SIGTERM))
    #expect(new.terminationStatus == .signalled(oldSignal))
  }

  // MARK: - Policy rejection

  @Test("An unacceptable exit code throws, exactly where the old acceptable-codes path throws")
  func policyRejectionMatchesAcceptableCodes() async throws {
    await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(
        Self.old("exit 149").runUntilCompletion(withAcceptableExitCodes: [0]))
    }

    do {
      _ = try await Self.new("exit 149").run(output: .closed, error: .closed, exitPolicy: .mustExit([0]))
      Issue.record("Expected the code-list policy to reject exit 149")
    } catch let SubprocessError.unacceptableTermination(status, _, _, _) {
      #expect(status == .exited(149))
    } catch {
      Issue.record("Expected an unacceptableTermination error, got: \(error)")
    }
  }

  @Test("A signal fails a zero-exit policy, matching the old path's rejection of signalled processes")
  func signalRejectionMatchesTheOldPath() async throws {
    await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(
        Self.old("kill -9 $$").runUntilCompletion(withAcceptableExitCodes: nil))
    }

    do {
      _ = try await Self.new("kill -9 $$").run(output: .closed, error: .closed)
      Issue.record("Expected the zero-exit policy to reject a signalled process")
    } catch let SubprocessError.unacceptableTermination(status, _, _, _) {
      #expect(status == .signalled(SIGKILL))
    } catch {
      Issue.record("Expected an unacceptableTermination error, got: \(error)")
    }
  }
}
