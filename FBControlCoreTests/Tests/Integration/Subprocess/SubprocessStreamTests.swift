/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Covers `Subprocess.stream`: output arrives in order and in full, the child
/// is held back by a slow consumer, and the process does not outlive a
/// consumer that throws or a task that is cancelled.
///
/// Serialized for the same reason as `SubprocessRunTests`: concurrent
/// spawning under suite load produces transient launch failures.
@Suite(.serialized)
struct SubprocessStreamTests {

  private static func shell(_ script: String) -> Subprocess {
    Subprocess(executable: "/bin/sh", arguments: ["-c", script])
  }

  private static func temporaryPath() -> String {
    (NSTemporaryDirectory() as NSString).appendingPathComponent("SubprocessStreamTests-\(UUID().uuidString)")
  }

  private static func processIdentifier(writtenTo path: String) async throws -> pid_t {
    for _ in 0..<500 {
      if let contents = try? String(contentsOfFile: path, encoding: .utf8), let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return pid
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("No process identifier was written to \(path)")
    return 0
  }

  private static func isAlive(_ processIdentifier: pid_t) -> Bool {
    kill(processIdentifier, 0) == 0
  }

  private struct ConsumerFailure: Error {}

  @Test("Every byte of stdout arrives, in order, across many chunks")
  func deliversAllOutputInOrder() async throws {
    var received = Data()
    var chunks = 0

    let completed = try await Self.shell("/usr/bin/seq 1 10000").stream(error: .closed, chunkSize: 256) { data in
      received.append(data)
      chunks += 1
    }

    let expected = (1...10000).map(String.init).joined(separator: "\n") + "\n"
    #expect(String(data: received, encoding: .utf8) == expected)
    #expect(chunks > 1)
    #expect(completed.terminationStatus == .exited(0))
  }

  @Test("A consumer that has not returned holds the child back")
  func aSlowConsumerStallsTheChild() async throws {
    let marker = Self.temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: marker) }
    var markerExistedDuringFirstChunk: Bool?

    // Far more than a pipe holds, so the child cannot reach the touch until it has been read.
    _ = try await Self.shell("/usr/bin/head -c 4194304 /dev/zero; /usr/bin/touch '\(marker)'").stream(error: .closed) { _ in
      guard markerExistedDuringFirstChunk == nil else {
        return
      }
      try await Task.sleep(for: .milliseconds(500))
      markerExistedDuringFirstChunk = FileManager.default.fileExists(atPath: marker)
    }

    #expect(markerExistedDuringFirstChunk == false)
    #expect(FileManager.default.fileExists(atPath: marker))
  }

  @Test("A rejected exit quotes the tail of the error-message capture")
  func rejectionQuotesTheErrorMessage() async throws {
    let logger = FBControlCoreLoggerFactory.logger(to: FBDataBuffer.consumableBuffer())

    let error = await #expect(throws: SubprocessError.self) {
      _ = try await Self.shell("printf 'out'; printf 'boom' 1>&2; exit 3").stream(error: .loggerCapturingErrorMessage(logger)) { _ in }
    }

    guard case let .unacceptableTermination(status, _, _, _, errorMessage) = error else {
      Issue.record("Expected an unacceptable termination, got \(String(describing: error))")
      return
    }
    #expect(status == .exited(3))
    #expect(errorMessage == "boom")
  }

  @Test("An acceptable non-zero exit is returned with its captured stderr")
  func anAcceptedExitReturnsTheCapture() async throws {
    let completed = try await Self.shell("printf 'err' 1>&2; exit 2").stream(error: .string, exitPolicy: .any) { _ in }

    #expect(completed.terminationStatus == .exited(2))
    #expect(completed.standardError == "err")
  }

  @Test("A consumer that throws terminates the child and rethrows")
  func aThrowingConsumerTerminatesTheChild() async throws {
    let pidFile = Self.temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: pidFile) }

    await #expect(throws: ConsumerFailure.self) {
      _ = try await Self.shell("echo $$ > '\(pidFile)'; exec /usr/bin/yes").stream(error: .closed, gracePeriod: 1) { _ in
        throw ConsumerFailure()
      }
    }

    let pid = try await Self.processIdentifier(writtenTo: pidFile)
    #expect(!Self.isAlive(pid))
  }

  @Test("Cancelling a stream blocked on a silent child terminates the child")
  func cancellationTerminatesASilentChild() async throws {
    let pidFile = Self.temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: pidFile) }

    let task = Task {
      try await Self.shell("echo $$ > '\(pidFile)'; exec /bin/sleep 10000").stream(error: .closed, gracePeriod: 1) { _ in }
    }
    let pid = try await Self.processIdentifier(writtenTo: pidFile)
    task.cancel()

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
    #expect(!Self.isAlive(pid))
  }
}
