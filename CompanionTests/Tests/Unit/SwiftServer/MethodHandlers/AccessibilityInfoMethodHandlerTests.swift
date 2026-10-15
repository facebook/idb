/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import FBSimulatorAX
import FBSimulatorControl
import Foundation
import GRPCCore
import IDBGRPCSwift
import Testing

/// Records the options the handler hands the command executor, so a test can read them without a
/// simulator. `IDBCommandExecutor` is a `public final class`; `AccessibilityDescribing` is the seam
/// the handler is written against, and this double stands in for it.
// SAFETY: each test makes one call at a time and reads the recording after it returns.
// patternlint-disable-next-line unchecked-sendable
private final class RecordingAccessibilityExecutor: AccessibilityDescribing, @unchecked Sendable {
  private(set) var describeOptions: AccessibilityRequestOptions?
  private(set) var describeQuery: AccessibilityElementQuery?
  private(set) var pointReadCount = 0
  private let response: AccessibilityElementsResponse

  init(response: AccessibilityElementsResponse = AccessibilityElementsResponse(elements: .single(AccessibilityDocumentElement()))) {
    self.response = response
  }

  func accessibilityDescribeResponse(
    query: AccessibilityElementQuery,
    options: AccessibilityRequestOptions,
    backend: UIAutomationBackend
  ) async throws -> AccessibilityElementsResponse {
    describeQuery = query
    describeOptions = options
    return response
  }

  func accessibilityInfoAtPoint(
    _ value: NSValue?,
    options: AccessibilityRequestOptions,
    backend: UIAutomationBackend
  ) async throws -> AccessibilityElementsResponse {
    pointReadCount += 1
    return response
  }
}

/// Takes `delay` to answer every read, and counts the reads it finished.
private actor SlowAccessibilityExecutor: AccessibilityDescribing {
  private let delay: UInt64
  private(set) var finishedReads = 0

  init(delayNanoseconds: UInt64) {
    self.delay = delayNanoseconds
  }

  func accessibilityDescribeResponse(
    query: AccessibilityElementQuery, options: AccessibilityRequestOptions, backend: UIAutomationBackend
  ) async throws -> AccessibilityElementsResponse {
    try await read()
  }

  func accessibilityInfoAtPoint(
    _ value: NSValue?, options: AccessibilityRequestOptions, backend: UIAutomationBackend
  ) async throws -> AccessibilityElementsResponse {
    try await read()
  }

  private func read() async throws -> AccessibilityElementsResponse {
    // Stands in for a read that keeps going: an unstructured task does not inherit the caller's cancellation.
    let delay = self.delay
    await Task { try? await Task.sleep(nanoseconds: delay) }.value
    finishedReads += 1
    return AccessibilityElementsResponse(elements: .single(AccessibilityDocumentElement()))
  }
}

/// Asserts what the *handler* hands the executor, which is where a describe-by-marker can silently
/// lose the request's `--key`/`--profile`/`--collect-frame-coverage` by reaching the executor with a
/// format-only options set. `AccessibilityInfoRequestTranslation.options(from:)` carries them for
/// both paths, so coverage on that translation alone does not guard the marker path.
@Suite
struct AccessibilityInfoMethodHandlerTests {

  @Test
  func markerReadCarriesTheRequestedKeysToTheExecutor() async throws {
    let executor = RecordingAccessibilityExecutor()
    var request = Idb_AccessibilityInfoRequest()
    request.marker = "OK"
    request.keys = ["AXLabel"]

    _ = try await AccessibilityInfoMethodHandler.respond(to: request, using: executor)

    let options = try #require(
      executor.describeOptions, "a marker read must reach the describe executor, not the at-point path")
    let label = try #require(AXKeys(rawValue: "AXLabel"))
    #expect(
      options.keys == Set([label]),
      "the request's --key must reach the executor on the marker path, not a format-only default set")
    #expect(executor.pointReadCount == 0, "a marker read must not fall through to the at-point read")
  }

  @Test
  func markerReadCarriesProfilingAndFrameCoverageToTheExecutor() async throws {
    let executor = RecordingAccessibilityExecutor()
    var request = Idb_AccessibilityInfoRequest()
    request.marker = "OK"
    request.profile = true
    request.collectFrameCoverage = true

    _ = try await AccessibilityInfoMethodHandler.respond(to: request, using: executor)

    let options = try #require(executor.describeOptions)
    #expect(options.enableProfiling, "--profile is a read option and a marker read is a read")
    #expect(
      options.collectFrameCoverage, "--collect-frame-coverage is a read option and a marker read is a read")
  }

  // MARK: - Read telemetry

  private static let translatorResponse = AccessibilityElementsResponse(
    elements: .single(AccessibilityDocumentElement()),
    backend: .ax,
    translatorMetrics: AccessibilityTranslatorReadMetrics(
      elementCount: 114, roundTrips: 225, readDuration: 0.072, totalDuration: 0.081,
      translatorReads: .batched, transport: .bridge, acquireDuration: 0.004, springBoardCheckDuration: 0.002,
      acquireRoundTrips: 2, unansweredRequests: 1,
      slowestRequest: AccessibilityTranslatorRequestTiming(requestType: 4, duration: 0.031)))

  @Test(arguments: [false, true])
  func everyReadRecordsHowItWentWithoutAskingForAProfile(byMarker: Bool) async throws {
    let executor = RecordingAccessibilityExecutor(response: Self.translatorResponse)
    var request = Idb_AccessibilityInfoRequest()
    if byMarker {
      request.marker = "OK"
    }
    let call = CallTelemetry()

    let response = try await CallTelemetry.$current.withValue(call) {
      try await AccessibilityInfoMethodHandler.respond(to: request, using: executor)
    }

    #expect(
      call.ints == [
        "ax_element_count": 114, "ax_round_trips": 225, "ax_profile_read_ms": 72, "ax_profile_total_ms": 81,
        "ax_profile_acquire_ms": 4, "ax_springboard_check_ms": 2, "ax_acquire_round_trips": 2, "ax_request_timeouts": 1,
        "ax_slowest_request_ms": 31,
      ])
    #expect(
      call.normals == [
        "ax_backend": "ax", "ax_translator_reads": "batched", "ax_transport": "bridge", "ax_read_outcome": "degraded",
        "ax_slowest_request_type": "frontmost",
      ])
    #expect(!response.json.contains("profile"), "the caller did not ask for a profile, so none is reported")
  }

  @Test
  func cancellingTheRPCStopsTheRead() async throws {
    let executor = SlowAccessibilityExecutor(delayNanoseconds: 300_000_000)
    let cancellation = ServerContext.RPCCancellationHandle()
    let read = Task {
      try await AccessibilityInfoMethodHandler.respond(to: Idb_AccessibilityInfoRequest(), using: executor, cancellation: cancellation)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    cancellation.cancel()
    await #expect(throws: CancellationError.self) { _ = try await read.value }
  }

  @Test
  func aReadThatRanOutOfTimeRecordsHowItEnded() {
    let unanswered = CallTelemetry()
    AccessibilityReadTelemetry.record(
      failure: AccessibilityError.serviceNotAnswering(.request(kind: "frontmost", timeout: 5), elapsed: 5), into: unanswered)
    #expect(unanswered.normals == ["ax_read_outcome": "aborted_unanswered"])

    let deadline = CallTelemetry()
    AccessibilityReadTelemetry.record(
      failure: AccessibilityError.serviceNotAnswering(.query(timeout: 10), elapsed: 10), into: deadline)
    #expect(deadline.normals == ["ax_read_outcome": "aborted_deadline"])

    let other = CallTelemetry()
    AccessibilityReadTelemetry.record(failure: AccessibilityError.springBoardNotRunning, into: other)
    #expect(other.normals.isEmpty, "a failure that is not about time says nothing about the outcome")
  }

  @Test
  func aReadWithoutTranslatorMetricsRecordsOnlyItsBackend() {
    let call = CallTelemetry()
    AccessibilityReadTelemetry.record(
      AccessibilityElementsResponse(elements: .single(AccessibilityDocumentElement()), backend: .axBridgeExclusive), into: call)
    #expect(call.ints.isEmpty)
    #expect(call.normals == ["ax_backend": "axbridge-exclusive"])
  }
}
