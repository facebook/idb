/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Covers `Subprocess.Input` and the detached `InputSource`.
///
/// Serialized for the same reason as `SubprocessRunTests`: concurrent
/// spawning under suite load produces transient launch failures.
/// A stdin that is never closed hangs the child forever rather than failing,
/// so the suite caps each test instead of letting one exhaust the run's
/// deadline and strand the rest as skipped.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SubprocessInputTests {

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

  @Test("A source written while the child runs delivers every chunk")
  func liveSourceDeliversEveryChunk() async throws {
    let chunks = ["first\n", "second\n", "third\n"]

    let source = InputSource()
    let output = FBDataBuffer.accumulatingBuffer()
    let running = try await Self.new("cat").launch(
      output: .consumer(output),
      error: .closed,
      input: .source(source))
    for chunk in chunks {
      source.write(Data(chunk.utf8))
    }
    source.finish()

    #expect(try await running.terminationStatus == .exited(0))
    #expect(String(data: output.data(), encoding: .utf8) == chunks.joined())
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

  @Test("An awaited write returns only once the child has read enough to take it")
  func awaitedWriteIsPacedByTheChild() async throws {
    let source = InputSource()
    let running = try await Self.new("sleep 1; cat > /dev/null").launch(output: .nullDevice, error: .nullDevice, input: .source(source))
    // Well past any pipe buffer, so the pipe cannot absorb it before the child reads.
    let payload = Data(count: 4 * 1024 * 1024)

    let start = Date()
    try await source.writeAndWait(payload)

    #expect(Date().timeIntervalSince(start) > 0.5)
    source.finish()
    #expect(try await running.terminationStatus == .exited(0))
  }

  @Test("An awaited write to a child that has exited throws")
  func awaitedWriteToAnExitedChildThrows() async throws {
    let source = InputSource()
    let running = try await Self.new("exit 0").launch(output: .nullDevice, error: .nullDevice, input: .source(source))
    #expect(try await running.terminationStatus == .exited(0))

    await #expect(throws: SubprocessError.self) {
      try await source.writeAndWait(Data(count: 4 * 1024 * 1024))
    }
  }

  @Test("Awaited writes made before the child launches are flushed")
  func awaitedWritesBeforeLaunchAreFlushed() async throws {
    let source = InputSource()
    try await source.writeAndWait(Data("early\n".utf8))
    source.finish()

    let completed = try await Self.new("cat").run(output: .string, error: .closed, input: .source(source))

    #expect(completed.standardOutput == "early")
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
