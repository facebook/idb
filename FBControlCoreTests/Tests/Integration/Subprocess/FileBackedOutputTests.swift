/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing
import os

/// Covers `FileBackedOutput`, driven by real processes that are handed the
/// path as an argument and write to it themselves, as a CoreSimulator app or
/// the xctest shim does.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct FileBackedOutputTests {

  private static func writing(_ script: String, to output: FileBackedOutput) async throws {
    _ = try await Subprocess(executable: "/bin/sh", arguments: ["-c", script, "sh", output.path]).run(output: .closed, error: .closed)
  }

  @Test("What the process writes to the FIFO reaches the consumer, followed by end-of-file")
  func fifoDrainsIntoTheConsumer() async throws {
    let buffer = FBDataBuffer.accumulatingBuffer()
    let output = try FileBackedOutput.fifo(draining: buffer)

    try await Self.writing("printf 'hello\\nworld\\n' > \"$1\"", to: output)
    let finishing = ContinuousClock.now
    await output.finish()

    #expect(ContinuousClock.now - finishing < .seconds(1), "Finishing after the writer has exited does not wait out the drain grace period")

    _ = try await bridgeFBFuture(buffer.finishedConsuming)
    #expect(buffer.lines() == ["hello", "world", ""])
  }

  @Test("The drain survives the process closing and reopening the path")
  func fifoOutlivesAWriterClosingIt() async throws {
    let buffer = FBDataBuffer.accumulatingBuffer()
    let output = try FileBackedOutput.fifo(draining: buffer)

    try await Self.writing("echo first > \"$1\"; echo second > \"$1\"", to: output)
    let finishing = ContinuousClock.now
    await output.finish()

    #expect(ContinuousClock.now - finishing < .seconds(1))

    _ = try await bridgeFBFuture(buffer.finishedConsuming)
    #expect(buffer.lines() == ["first", "second", ""])
  }

  @Test("A writer still holding the FIFO open is abandoned after the grace period, ending the consumer")
  func fifoAbandonsALingeringWriter() async throws {
    let buffer = FBDataBuffer.accumulatingBuffer()
    let output = try FileBackedOutput.fifo(draining: buffer)
    let lingering = try await Subprocess(executable: "/bin/sh", arguments: ["-c", "exec 3>\"$1\"; echo early >&3; exec sleep 30", "sh", output.path]).launch(output: .closed, error: .closed)
    defer { lingering.sendSignal(SIGKILL) }
    try await Task.sleep(nanoseconds: 500_000_000)

    let finishing = ContinuousClock.now
    await output.finish()

    #expect(ContinuousClock.now - finishing >= .seconds(HostSubprocess.drainTimeout))
    _ = try await bridgeFBFuture(buffer.finishedConsuming)
    #expect(buffer.lines() == ["early", ""])
  }

  @Test("A FIFO that no process ever opened still finishes, with end-of-file and nothing else")
  func fifoFinishesWithoutAWriter() async throws {
    let buffer = FBDataBuffer.accumulatingBuffer()
    let output = try FileBackedOutput.fifo(draining: buffer)

    await output.finish()

    _ = try await bridgeFBFuture(buffer.finishedConsuming)
    #expect(buffer.data().isEmpty)
  }

  @Test("Concurrent finishes of a FIFO with a lingering writer all return once the grace period ends")
  func fifoReleasesEveryConcurrentFinish() async throws {
    let output = try FileBackedOutput.fifo(draining: FBDataBuffer.accumulatingBuffer())
    let lingering = open(output.path, O_WRONLY)
    try #require(lingering >= 0)
    defer { close(lingering) }
    let finished = OSAllocatedUnfairLock(initialState: 0)

    for _ in 0..<2 {
      Task {
        await output.finish()
        finished.withLock { $0 += 1 }
      }
    }
    try await Task.sleep(for: .seconds(HostSubprocess.drainTimeout + 2))

    // BUG: the second finish replaces the first's waiter, so the first never returns — flipped in the following commit.
    #expect(finished.withLock { $0 } == 1)
  }

  @Test("The FIFO exists for the process before launch and is removed once finished")
  func fifoIsMaterialisedUntilFinished() async throws {
    let output = try FileBackedOutput.fifo(draining: FBDataBuffer.accumulatingBuffer())

    var info = stat()
    #expect(stat(output.path, &info) == 0)
    #expect(info.st_mode & S_IFMT == S_IFIFO)

    await output.finish()

    #expect(!FileManager.default.fileExists(atPath: output.path))
  }

  @Test("A file output hands the process the path it was given, and finishing it leaves the file alone")
  func fileIsWrittenDirectly() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let output = FileBackedOutput.file(url.path)

    try await Self.writing("echo direct > \"$1\"", to: output)
    await output.finish()

    #expect(output.path == url.path)
    #expect(try String(contentsOf: url, encoding: .utf8) == "direct\n")
  }

  @Test("The null device discards what the process writes")
  func nullDeviceDiscards() async throws {
    let output = FileBackedOutput.nullDevice

    try await Self.writing("echo discarded > \"$1\"", to: output)
    await output.finish()

    #expect(output.path == "/dev/null")
  }
}
