/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest
import XCTestBootstrap

/// Pins how `FBXCTestResultToolOperation` launches `xcrun xcresulttool` and what a
/// caller sees when it fails: which exit-code policy applies, and what reaches an
/// optional logger.
///
/// Nothing here asserts a desirable design. Each case records what callers observe
/// today so that a later replacement has to either reproduce it or change it
/// deliberately.
final class FBXCTestResultToolOperationTests: XCTestCase {

  private var temporaryDirectory: URL!
  private let queue = DispatchQueue(label: "com.facebook.xctestbootstrap.tests.xcresulttool")

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FBXCTestResultToolOperationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
    temporaryDirectory = nil
    try super.tearDownWithError()
  }

  private var absentResultBundlePath: String {
    temporaryDirectory.appendingPathComponent("Absent.xcresult").path
  }

  // MARK: - Exit code policy

  func testGettingJSONFailsWhenTheToolExitsNonZero() async throws {
    do {
      _ = try await bridgeFBFuture(
        FBXCTestResultToolOperation.getJSON(from: absentResultBundlePath, forId: nil, queue: queue, logger: nil))
      XCTFail("Expected reading an absent result bundle to fail")
    } catch {
      // Every entry point launches with `[0]` as the only acceptable exit code, so a
      // failure surfaces as the launcher's exit-code rejection rather than as
      // anything `xcresulttool` said about the request.
      XCTAssertTrue(error.localizedDescription.contains("is not acceptable"), error.localizedDescription)
    }
  }

  func testExportingAFileFailsWhenTheToolExitsNonZero() async throws {
    do {
      _ = try await bridgeFBFuture(
        FBXCTestResultToolOperation.exportFile(
          from: absentResultBundlePath,
          to: temporaryDirectory.appendingPathComponent("out.bin").path,
          forId: "0~abcdef",
          queue: queue,
          logger: nil))
      XCTFail("Expected exporting from an absent result bundle to fail")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("is not acceptable"), error.localizedDescription)
    }
  }

  func testAnUnrecognizedScreenshotEncodingIsMaskedByAnExportFailure() async throws {
    do {
      _ = try await bridgeFBFuture(
        FBXCTestResultToolOperation.exportJPEG(
          from: absentResultBundlePath,
          to: temporaryDirectory.appendingPathComponent("out.jpg").path,
          forId: "0~abcdef",
          type: "public.png",
          queue: queue,
          logger: nil))
      XCTFail("Expected the failing export to throw")
    } catch {
      // The export runs first, so an unusable result bundle masks the encoding
      // check entirely — the caller never learns the encoding was wrong.
      XCTAssertTrue(error.localizedDescription.contains("is not acceptable"), error.localizedDescription)
      XCTAssertFalse(error.localizedDescription.contains("Unrecognized XCTest screenshot encoding"), error.localizedDescription)
    }
  }

  // MARK: - Logging

  func testASuppliedLoggerReceivesBothTheLaunchAndTheToolsStandardError() async throws {
    // What the tool writes to stderr for this exact invocation, captured by running
    // it directly. Asserting against this rather than a hardcoded message keeps the
    // case pinned to stderr forwarding itself, whatever the current toolchain emits.
    let capturedStdErr = try await standardError(
      ofDirectlyRunning: ["xcresulttool", "get", "--path", absentResultBundlePath, "--format", "json"])
    guard !capturedStdErr.isEmpty else {
      return XCTFail("xcresulttool wrote nothing to stderr for a failing get; this case needs a stderr-producing invocation to pin forwarding")
    }

    // A logger is the only way to see the tool's stderr from these entry points:
    // `withStdErr(to:)` is applied only when one is supplied, and every failing
    // launch throws the exit-code rejection rather than returning the process.
    let logger = RecordingLogger()

    do {
      _ = try await bridgeFBFuture(
        FBXCTestResultToolOperation.getJSON(from: absentResultBundlePath, forId: nil, queue: queue, logger: logger))
    } catch {
      // The failure itself is covered above; this case is about what was logged.
    }

    let messages = logger.messages
    XCTAssertTrue(
      messages.contains { $0.contains("Launched with pid") },
      "Lifecycle logging should announce the launch: \(messages)")

    // The tool's stderr is not forwarded line by line. It arrives as arbitrary read
    // chunks, trimmed of newlines at each chunk's edges.
    // BUG: each chunk is delivered twice — the logger output path attaches two
    // logging consumers to the same logger.
    //
    // The walk below verifies the whole of the captured stderr reached the logger
    // in order, whatever the chunking: a message that continues the expected text
    // consumes it, its duplicate is expected to follow immediately, and anything
    // else (the lifecycle lines) is passed over.
    var remainder = Substring(capturedStdErr.replacingOccurrences(of: "\n", with: ""))
    var unpaired = [String]()
    var index = 0
    while index < messages.count {
      let chunk = messages[index].replacingOccurrences(of: "\n", with: "")
      guard !chunk.isEmpty, remainder.hasPrefix(chunk) else {
        index += 1
        continue
      }
      remainder = remainder.dropFirst(chunk.count)
      if index + 1 < messages.count, messages[index + 1] == messages[index] {
        index += 2
      } else {
        unpaired.append(messages[index])
        index += 1
      }
    }
    XCTAssertTrue(
      remainder.isEmpty,
      "The whole of the tool's stderr should reach the logger; never received: \(remainder) given: \(messages)")
    XCTAssertTrue(
      unpaired.isEmpty,
      "Every stderr chunk is currently delivered to the logger twice; these arrived once: \(unpaired)")
  }

  private func standardError(ofDirectlyRunning arguments: [String]) async throws -> String {
    let process = try await bridgeFBFuture(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/usr/bin/xcrun", arguments: arguments)
        .withStdErrInMemoryAsString()
        .runUntilCompletion(withAcceptableExitCodes: nil))
    return (process.stdErr as String?) ?? ""
  }
}

// MARK: - Logger double

/// Records every line handed to it, so a test can assert on what a process forwarded.
private final class RecordingLogger: NSObject, FBControlCoreLogger, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []

  var messages: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }

  func log(_ message: String) -> any FBControlCoreLogger {
    lock.lock()
    recorded.append(message)
    lock.unlock()
    return self
  }

  func info() -> any FBControlCoreLogger { self }
  func debug() -> any FBControlCoreLogger { self }
  func error() -> any FBControlCoreLogger { self }
  func withName(_ name: String) -> any FBControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any FBControlCoreLogger { self }
}
