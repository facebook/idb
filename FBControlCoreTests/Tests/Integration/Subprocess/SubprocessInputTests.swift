/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Covers `Subprocess.Input` and the detached `InputSource`. The two forms
/// that `FBProcessInput` already supports — a fixed blob and an externally
/// written consumer — are covered differentially against it, so the façade's
/// stdin is checkably the same stdin. The buffering of writes made before the
/// child launches has no counterpart to compare against: `FBProcessInput`
/// forwards to a writer that does not exist until attach, so those writes are
/// dropped.
///
/// Serialized for the same reason as `SubprocessRunTests`: concurrent
/// spawning under suite load produces transient launch failures.
/// A stdin that is never closed hangs the child forever rather than failing,
/// so the suite caps each test instead of letting one exhaust the run's
/// deadline and strand the rest as skipped.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SubprocessInputTests {

  private static func old(_ script: String) -> FBProcessBuilder<NSNull, NSData, NSData> {
    FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/bin/sh", arguments: ["-c", script])
  }

  private static func new(_ script: String) -> Subprocess {
    Subprocess(executable: "/bin/sh", arguments: ["-c", script])
  }

  // MARK: - The empty spellings

  @Test("A closed stdin gives the child no descriptor to read")
  func closedStdinIsUnreadable() async throws {
    // `cat` reports the bad descriptor and exits non-zero; the point is that
    // the read fails rather than seeing end-of-file.
    let completed = try await Self.new("cat").run(output: .string, error: .string, input: .closed, exitPolicy: .any)

    #expect(completed.terminationStatus != .exited(0))
    #expect(completed.standardOutput.isEmpty)
  }

  @Test("A null-device stdin gives the child immediate end-of-file")
  func nullDeviceStdinIsEmpty() async throws {
    let completed = try await Self.new("cat").run(output: .string, error: .string, input: .nullDevice)

    #expect(completed.terminationStatus == .exited(0))
    #expect(completed.standardOutput.isEmpty)
    #expect(completed.standardError.isEmpty)
  }

  @Test("Stdin defaults to closed, as every launch had it before it was configurable")
  func stdinDefaultsToClosed() async throws {
    let completed = try await Self.new("cat").run(output: .string, error: .string, exitPolicy: .any)

    #expect(completed.terminationStatus != .exited(0))
  }

  // MARK: - A fixed blob

  private static let payload = "the payload\nover two lines"

  @Test("A data input is echoed back by the child")
  func dataInputIsEchoed() async throws {
    let new = try await Self.new("cat").run(output: .string, error: .closed, input: .data(Data(Self.payload.utf8)))

    #expect(new.standardOutput == Self.payload)
  }

  @Test("A data input delivers the same bytes as the builder's data stdin")
  func dataInputMatchesTheBuilder() async throws {
    let old = try await bridgeFBFuture(
      Self.old("cat")
        .withStdIn(from: Data(Self.payload.utf8))
        .withStdOutInMemoryAsString()
        .runUntilCompletion(withAcceptableExitCodes: [0]))
    let new = try await Self.new("cat").run(output: .string, error: .closed, input: .data(Data(Self.payload.utf8)))

    #expect((old.stdOut as? String) == Self.payload)
    #expect(new.standardOutput == (old.stdOut as? String))
  }

  @Test("An empty data input is end-of-file, not a closed descriptor")
  func emptyDataInputIsEndOfFile() async throws {
    let completed = try await Self.new("cat").run(output: .string, error: .string, input: .data(Data()))

    #expect(completed.terminationStatus == .exited(0))
    #expect(completed.standardOutput.isEmpty)
  }

  // MARK: - The pipe, independent of any spawn

  @Test("Attaching flushes what was written, then closes the pipe")
  func attachDeliversBytesThenEndOfFile() async throws {
    let source = InputSource()
    source.write(Data("hello".utf8))
    source.finish()

    let readEnd = try source.attach()
    defer { close(readEnd) }

    var received = Data()
    var buffer = [UInt8](repeating: 0, count: 64)
    while true {
      let count = read(readEnd, &buffer, buffer.count)
      guard count > 0 else {
        break
      }
      received.append(contentsOf: buffer[0..<count])
    }

    #expect(String(data: received, encoding: .utf8) == "hello")
  }

  // MARK: - The detached source

  @Test("A source written while the child runs delivers the same bytes as the builder's connected stdin")
  func liveSourceMatchesTheBuilder() async throws {
    let chunks = ["first\n", "second\n", "third\n"]

    let started = try await bridgeFBFuture(
      Self.old("cat")
        .withStdInConnected()
        .withStdOutInMemoryAsString()
        .start())
    let stdIn = try #require(started.stdIn)
    for chunk in chunks {
      stdIn.consumeData(Data(chunk.utf8))
    }
    stdIn.consumeEndOfFile()
    _ = try await bridgeFBFuture(started.exited(withCodes: [0]))

    let source = InputSource()
    let backing = NSMutableData()
    let running = try await Self.new("cat").launch(
      output: .consumer(FBDataBuffer.accumulatingBuffer(for: backing)),
      error: .closed,
      input: .source(source))
    for chunk in chunks {
      source.write(Data(chunk.utf8))
    }
    source.finish()

    #expect(try await running.terminationStatus == .exited(0))
    // The builder's string capture strips one trailing newline; the raw
    // consumer capture here does not, so the comparison restores it.
    #expect(String(data: backing as Data, encoding: .utf8) == chunks.joined())
    #expect(String(data: backing as Data, encoding: .utf8) == (started.stdOut as? String).map { $0 + "\n" })
  }

  @Test("A source finished without a write is end-of-file")
  func finishedWithoutWritingIsEndOfFile() async throws {
    let source = InputSource()
    source.finish()
    let completed = try await Self.new("cat").run(output: .string, error: .string, input: .source(source))

    #expect(completed.terminationStatus == .exited(0))
    #expect(completed.standardOutput.isEmpty)
  }

  @Test("Writes made before the child launches are flushed rather than dropped")
  func writesBeforeLaunchAreFlushed() async throws {
    let source = InputSource()
    source.write(Data("early\n".utf8))
    source.write(Data("also early\n".utf8))
    source.finish()

    let completed = try await Self.new("cat").run(output: .string, error: .closed, input: .source(source))

    #expect(completed.standardOutput == "early\nalso early")
  }

  @Test("Writes after finishing are ignored")
  func writesAfterFinishingAreIgnored() async throws {
    let source = InputSource()
    source.write(Data("kept\n".utf8))
    source.finish()
    source.write(Data("dropped\n".utf8))

    let completed = try await Self.new("cat").run(output: .string, error: .closed, input: .source(source))

    #expect(completed.standardOutput == "kept")
  }

  @Test("A source cannot be attached to a second launch")
  func attachingTwiceFails() async throws {
    let source = InputSource()
    // The child echoes to the null device rather than to a closed descriptor,
    // so its exit reflects only what happened to its stdin.
    let running = try await Self.new("cat").launch(output: .nullDevice, error: .nullDevice, input: .source(source))

    await #expect(throws: SubprocessError.self) {
      _ = try await Self.new("cat").run(output: .nullDevice, error: .nullDevice, input: .source(source))
    }

    source.finish()
    #expect(try await running.terminationStatus == .exited(0))
  }
}
