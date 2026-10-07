/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import FBVideoCore
import Foundation
import GRPCCore
import IDBGRPCSwift
import Testing

/// A recording whose `stop()` either returns a URL or fails, standing in for the finalize step.
private final class StubRecording: VideoRecording, @unchecked Sendable {
  private let result: Result<URL, any Error>

  init(_ result: Result<URL, any Error>) {
    self.result = result
  }

  func stop() async throws -> URL {
    try result.get()
  }
}

private final class RecordingLogger: NSObject, ControlCoreLogger, @unchecked Sendable {
  private let lock = NSLock()
  private var logged: [String] = []

  var messages: [String] {
    lock.lock()
    defer { lock.unlock() }
    return logged
  }

  @discardableResult
  func log(_ message: String) -> any ControlCoreLogger {
    lock.lock()
    logged.append(message)
    lock.unlock()
    return self
  }

  func info() -> any ControlCoreLogger { self }
  func debug() -> any ControlCoreLogger { self }
  func error() -> any ControlCoreLogger { self }
  func withName(_ name: String) -> any ControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any ControlCoreLogger { self }
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }
}

private struct StubError: Error, CustomStringConvertible {
  let description: String
}

/// Collects everything written so a test can see what reached the client before an error did.
private final class CollectingWriter<Element: Sendable>: RPCWriterProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var written: [Element] = []

  var elements: [Element] {
    lock.lock()
    defer { lock.unlock() }
    return written
  }

  func write(_ element: Element) async throws {
    lock.lock()
    written.append(element)
    lock.unlock()
  }

  func write(contentsOf elements: some Sequence<Element>) async throws {
    for element in elements {
      try await write(element)
    }
  }
}

/// Decompresses with the system `gzip`, as a client does.
private func gunzip(_ data: Data) throws -> Data {
  let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("record-gunzip-\(UUID().uuidString).gz")
  try data.write(to: file)
  defer { try? FileManager.default.removeItem(at: file) }
  let gzip = Process()
  gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
  gzip.arguments = ["-dc", file.path]
  let output = Pipe()
  gzip.standardOutput = output
  try gzip.run()
  let decompressed = output.fileHandleForReading.readDataToEndOfFile()
  gzip.waitUntilExit()
  #expect(gzip.terminationStatus == 0)
  return decompressed
}

@Suite
struct RecordMethodHandlerTests {

  /// The ordinary path is unchanged: the URL the recorder reports is the one delivered.
  @Test
  func finalizeReportsTheRecordedFileWhenStoppingSucceeds() async {
    let recorded = URL(fileURLWithPath: "/tmp/recorded.mp4")
    let logger = RecordingLogger()

    let (outputURL, finalizeError) = await RecordMethodHandler.finalizeForDelivery(
      StubRecording(.success(recorded)),
      fallbackPath: "/tmp/started-against.mp4",
      logger: logger)

    #expect(outputURL == recorded)
    #expect(finalizeError == nil)
    #expect(logger.messages.isEmpty)
  }

  /// The failure this exists for: the frames are already on disk, so a finalize that fails must
  /// still yield a file to send. Throwing instead skipped the transfer and the caller received
  /// nothing at all.
  @Test
  func finalizeStillYieldsAFileToSendWhenStoppingFails() async {
    let startedAgainst = "/tmp/started-against.mp4"
    let failure = StubError(description: "AVAssetWriter failed to finish writing")
    let logger = RecordingLogger()

    let (outputURL, finalizeError) = await RecordMethodHandler.finalizeForDelivery(
      StubRecording(.failure(failure)),
      fallbackPath: startedAgainst,
      logger: logger)

    #expect(outputURL == URL(fileURLWithPath: startedAgainst))
    #expect(finalizeError != nil)
  }

  /// The failure is returned, not swallowed: the caller reports it after delivering the file, so a
  /// broken recording is never silently presented as a good one.
  @Test
  func finalizeHandsBackTheOriginalFailure() async {
    let failure = StubError(description: "sentinel finalize failure")

    let (_, finalizeError) = await RecordMethodHandler.finalizeForDelivery(
      StubRecording(.failure(failure)),
      fallbackPath: "/tmp/started-against.mp4",
      logger: RecordingLogger())

    #expect((finalizeError as? StubError)?.description == failure.description)
  }

  /// A dropped recording is worth a line in the companion log, since the client only learns the
  /// file is short and not why.
  @Test
  func finalizeLogsWhyTheRecordingWasNotFinalized() async {
    let logger = RecordingLogger()

    _ = await RecordMethodHandler.finalizeForDelivery(
      StubRecording(.failure(StubError(description: "sentinel finalize failure"))),
      fallbackPath: "/tmp/started-against.mp4",
      logger: logger)

    #expect(logger.messages.contains { $0.contains("sentinel finalize failure") })
  }

  /// The claim the fix exists to make: a recording that failed to finalize is still delivered, and
  /// the failure is reported only afterwards. Before the fix the error was raised first and the
  /// caller received nothing at all.
  @Test
  func deliveryHappensBeforeTheFinalizeFailureIsReported() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("record-deliver-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorded = directory.appendingPathComponent("segment_001.mp4")
    try Data(repeating: 0xAB, count: 64 * 1024).write(to: recorded)

    let collector = CollectingWriter<Idb_RecordResponse>()
    let failure = StubError(description: "AVAssetWriter failed to finish writing")

    var thrown: (any Error)?
    do {
      try await RecordMethodHandler.deliverThenReport(
        outputURL: recorded,
        streamingToClient: true,
        localFilePath: "",
        finalizeError: failure,
        responseStream: RPCWriter(wrapping: collector),
        logger: RecordingLogger())
    } catch {
      thrown = error
    }

    // The failure still fails the RPC...
    #expect((thrown as? StubError)?.description == failure.description)
    // ...but the bytes went out first, which is what was being thrown away.
    let delivered = collector.elements.reduce(0) { $0 + $1.payload.data.count }
    #expect(delivered > 0, "expected the recording to be sent before the failure was reported")
  }

  /// Nothing to send and gzip would fail on the missing path with an error that hides the real one,
  /// so the transfer is skipped and the finalize failure is still what surfaces.
  @Test
  func aMissingFileIsNotSentAndTheFinalizeFailureStillSurfaces() async {
    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("absent-\(UUID().uuidString).mp4")
    let collector = CollectingWriter<Idb_RecordResponse>()
    let failure = StubError(description: "sentinel finalize failure")

    var thrown: (any Error)?
    do {
      try await RecordMethodHandler.deliverThenReport(
        outputURL: missing,
        streamingToClient: true,
        localFilePath: "",
        finalizeError: failure,
        responseStream: RPCWriter(wrapping: collector),
        logger: RecordingLogger())
    } catch {
      thrown = error
    }

    #expect((thrown as? StubError)?.description == failure.description)
    #expect(collector.elements.isEmpty)
  }

  /// The ordinary path is untouched: a clean finalize delivers the recording, gzipped, and returns without throwing.
  @Test
  func aCleanFinalizeDeliversAndDoesNotThrow() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("record-clean-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorded = directory.appendingPathComponent("segment_001.mp4")
    try Data(repeating: 0xCD, count: 32 * 1024).write(to: recorded)

    let collector = CollectingWriter<Idb_RecordResponse>()

    try await RecordMethodHandler.deliverThenReport(
      outputURL: recorded,
      streamingToClient: true,
      localFilePath: "",
      finalizeError: nil,
      responseStream: RPCWriter(wrapping: collector),
      logger: RecordingLogger())

    let delivered = collector.elements.reduce(into: Data()) { $0.append($1.payload.data) }
    #expect(try gunzip(delivered) == Data(contentsOf: recorded))
  }

  @Test(.enabled(if: getuid() != 0, "root reads a file whatever its mode"))
  func aRecordingThatCannotBeCompressedReportsTheExitCode() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("record-unreadable-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorded = directory.appendingPathComponent("segment_001.mp4")
    try Data(repeating: 0xCD, count: 1024).write(to: recorded)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: recorded.path)
    let collector = CollectingWriter<Idb_RecordResponse>()

    let error = await #expect(throws: RPCError.self) {
      try await RecordMethodHandler.deliverThenReport(
        outputURL: recorded,
        streamingToClient: true,
        localFilePath: "",
        finalizeError: nil,
        responseStream: RPCWriter(wrapping: collector),
        logger: RecordingLogger())
    }

    #expect(error?.message.hasPrefix("Draining operation failed with exit code 1: ") == true)
    #expect(error?.message.contains("Permission denied") == true)
    #expect(collector.elements.isEmpty)
  }
}
