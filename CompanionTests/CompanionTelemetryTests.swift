/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CompanionUtilities
@preconcurrency import FBControlCore
import Foundation
// Uses XCTest to match the existing tests in this target; migrating the whole
// target to Swift Testing is a separate effort.
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Captures every subject the telemetry reports, so the per-RPC emission can
/// be asserted without a scribe process.
private final class RecordingEventReporter: NSObject, FBEventReporter, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [FBEventReporterSubject] = []

  var subjects: [FBEventReporterSubject] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  var metadata: [String: String] { [:] }

  func report(_ subject: FBEventReporterSubject) {
    lock.lock()
    defer { lock.unlock() }
    recorded.append(subject)
  }

  func addMetadata(_ metadata: [String: String]) {}
}

private struct FetchRequest {
  let bundleID: String
  let verbose: Bool
}

private struct TelemetryTestError: Error, LocalizedError {
  var errorDescription: String? { "request exploded" }
}

final class CompanionTelemetryTests: XCTestCase {

  private static let logger = FBIDBLogger(
    loggers: [FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: false)])

  private func makeTelemetry() -> (CompanionTelemetry, RecordingEventReporter) {
    let recorder = RecordingEventReporter()
    return (CompanionTelemetry(logger: Self.logger, reporter: recorder), recorder)
  }

  func testUnaryCallSuccessReportsOneSuccessSubject() async throws {
    let (telemetry, recorder) = makeTelemetry()
    let request = FetchRequest(bundleID: "com.example.app", verbose: true)
    let value = try await telemetry.unaryCall("list_apps", request: request) { "ok" }
    XCTAssertEqual(value, "ok")
    // Pinned: exactly one terminal subject per RPC; no started subject.
    XCTAssertEqual(recorder.subjects.count, 1)
    let subject = recorder.subjects[0]
    XCTAssertEqual(subject.eventName, "list_apps")
    XCTAssertEqual(subject.eventType, .success)
    XCTAssertNotNil(subject.duration)
    XCTAssertNil(subject.size)
    XCTAssertEqual(subject.arguments, ["bundleID=com.example.app", "verbose=true"])
  }

  func testUnaryCallFailureReportsFailureSubjectAndRethrows() async {
    let (telemetry, recorder) = makeTelemetry()
    let request = FetchRequest(bundleID: "com.example.app", verbose: false)
    do {
      _ = try await telemetry.unaryCall("list_apps", request: request) { () async throws -> String in
        throw TelemetryTestError()
      }
      XCTFail("unaryCall should rethrow the body's error")
    } catch {
      XCTAssertTrue(error is TelemetryTestError)
    }
    XCTAssertEqual(recorder.subjects.count, 1)
    let subject = recorder.subjects[0]
    XCTAssertEqual(subject.eventName, "list_apps")
    XCTAssertEqual(subject.eventType, .failure)
    XCTAssertEqual(subject.message, "request exploded")
    XCTAssertNotNil(subject.duration)
  }

  func testClientStreamingReportsWithEmptyArguments() async throws {
    let (telemetry, recorder) = makeTelemetry()
    _ = try await telemetry.clientStreaming("push") { "done" }
    XCTAssertEqual(recorder.subjects.count, 1)
    let subject = recorder.subjects[0]
    XCTAssertEqual(subject.eventName, "push")
    XCTAssertEqual(subject.eventType, .success)
    XCTAssertEqual(subject.arguments, [])
  }

  func testServerStreamingSuccessReportsRequestArguments() async throws {
    let (telemetry, recorder) = makeTelemetry()
    let request = FetchRequest(bundleID: "com.example.app", verbose: false)
    try await telemetry.serverStreaming("pull", request: request) {}
    XCTAssertEqual(recorder.subjects.count, 1)
    let subject = recorder.subjects[0]
    XCTAssertEqual(subject.eventType, .success)
    XCTAssertEqual(subject.arguments, ["bundleID=com.example.app", "verbose=false"])
  }

  func testBidiStreamingFailureReportsFailureSubject() async {
    let (telemetry, recorder) = makeTelemetry()
    do {
      try await telemetry.bidiStreaming("repl") {
        throw TelemetryTestError()
      }
      XCTFail("bidiStreaming should rethrow the body's error")
    } catch {
      XCTAssertTrue(error is TelemetryTestError)
    }
    XCTAssertEqual(recorder.subjects.count, 1)
    let subject = recorder.subjects[0]
    XCTAssertEqual(subject.eventName, "repl")
    XCTAssertEqual(subject.eventType, .failure)
  }
}
