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
import Testing

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

/// Mirrors how SwiftProtobuf renders its per-request unknown-fields storage,
/// without importing SwiftProtobuf into the test target.
private struct EmptyUnknownStorage: CustomStringConvertible {
  var description: String { "UnknownStorage(data: 0 bytes)" }
}

private struct NonEmptyUnknownStorage: CustomStringConvertible {
  var description: String { "UnknownStorage(data: 3 bytes)" }
}

private struct RequestWithUnknownFields<Storage: CustomStringConvertible> {
  let bundleID: String
  let unknownFields: Storage
}

private struct TelemetryTestError: Error, LocalizedError {
  var errorDescription: String? { "request exploded" }
}

@Suite
struct CompanionTelemetryTests {

  private static let logger = FBIDBLogger(
    loggers: [FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: false)])

  private func makeTelemetry() -> (CompanionTelemetry, RecordingEventReporter) {
    let recorder = RecordingEventReporter()
    return (CompanionTelemetry(logger: Self.logger, reporter: recorder), recorder)
  }

  @Test
  func unaryCallSuccessReportsOneSuccessSubject() async throws {
    let (telemetry, recorder) = makeTelemetry()
    let request = FetchRequest(bundleID: "com.example.app", verbose: true)
    let value = try await telemetry.unaryCall("list_apps", request: request) { "ok" }
    #expect((value) == ("ok"))
    // Pinned: exactly one terminal subject per RPC; no started subject.
    #expect((recorder.subjects.count) == (1))
    let subject = recorder.subjects[0]
    #expect((subject.eventName) == ("list_apps"))
    #expect((subject.eventType) == (.success))
    #expect((subject.duration) != nil)
    #expect((subject.size) == nil)
    #expect((subject.arguments) == (["bundleID=com.example.app", "verbose=true"]))
  }

  @Test
  func unaryCallFailureReportsFailureSubjectAndRethrows() async {
    let (telemetry, recorder) = makeTelemetry()
    let request = FetchRequest(bundleID: "com.example.app", verbose: false)
    do {
      _ = try await telemetry.unaryCall("list_apps", request: request) { () async throws -> String in
        throw TelemetryTestError()
      }
      Issue.record("unaryCall should rethrow the body's error")
    } catch {
      #expect((error is TelemetryTestError))
    }
    #expect((recorder.subjects.count) == (1))
    let subject = recorder.subjects[0]
    #expect((subject.eventName) == ("list_apps"))
    #expect((subject.eventType) == (.failure))
    #expect((subject.message) == ("request exploded"))
    #expect((subject.duration) != nil)
  }

  @Test
  func clientStreamingReportsWithEmptyArguments() async throws {
    let (telemetry, recorder) = makeTelemetry()
    _ = try await telemetry.clientStreaming("push") { "done" }
    #expect((recorder.subjects.count) == (1))
    let subject = recorder.subjects[0]
    #expect((subject.eventName) == ("push"))
    #expect((subject.eventType) == (.success))
    #expect((subject.arguments) == ([]))
  }

  @Test
  func serverStreamingSuccessReportsRequestArguments() async throws {
    let (telemetry, recorder) = makeTelemetry()
    let request = FetchRequest(bundleID: "com.example.app", verbose: false)
    try await telemetry.serverStreaming("pull", request: request) {}
    #expect((recorder.subjects.count) == (1))
    let subject = recorder.subjects[0]
    #expect((subject.eventType) == (.success))
    #expect((subject.arguments) == (["bundleID=com.example.app", "verbose=false"]))
  }

  @Test
  func emptyUnknownFieldsAreOmittedFromArguments() async throws {
    let (telemetry, recorder) = makeTelemetry()
    let request = RequestWithUnknownFields(
      bundleID: "com.example.app",
      unknownFields: EmptyUnknownStorage(),
    )
    try await telemetry.unaryCall("list_apps", request: request) {}
    #expect((recorder.subjects.count) == (1))
    #expect((recorder.subjects[0].arguments) == (["bundleID=com.example.app"]))
  }

  @Test
  func nonEmptyUnknownFieldsAreKeptInArguments() async throws {
    let (telemetry, recorder) = makeTelemetry()
    let request = RequestWithUnknownFields(
      bundleID: "com.example.app",
      unknownFields: NonEmptyUnknownStorage(),
    )
    try await telemetry.unaryCall("list_apps", request: request) {}
    #expect((recorder.subjects.count) == (1))
    #expect(
      (recorder.subjects[0].arguments)
        == ([
          "bundleID=com.example.app",
          "unknownFields=UnknownStorage(data: 3 bytes)",
        ]))
  }

  @Test
  func bidiStreamingFailureReportsFailureSubject() async {
    let (telemetry, recorder) = makeTelemetry()
    do {
      try await telemetry.bidiStreaming("repl") {
        throw TelemetryTestError()
      }
      Issue.record("bidiStreaming should rethrow the body's error")
    } catch {
      #expect((error is TelemetryTestError))
    }
    #expect((recorder.subjects.count) == (1))
    let subject = recorder.subjects[0]
    #expect((subject.eventName) == ("repl"))
    #expect((subject.eventType) == (.failure))
  }
}
