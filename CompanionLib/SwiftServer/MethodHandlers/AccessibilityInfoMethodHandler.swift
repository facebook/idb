/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorAX
import FBSimulatorControl
import Foundation
import GRPCCore
import IDBGRPCSwift

/// Seam over the two `IDBCommandExecutor` reads this handler drives, so the request-to-options wiring
/// can be tested against a double.
protocol AccessibilityDescribing: Sendable {
  func accessibilityDescribeResponse(
    query: AccessibilityElementQuery,
    options: AccessibilityRequestOptions,
    backend: UIAutomationBackend
  ) async throws -> AccessibilityElementsResponse

  func accessibilityInfoAtPoint(
    _ value: NSValue?,
    options: AccessibilityRequestOptions,
    backend: UIAutomationBackend
  ) async throws -> AccessibilityElementsResponse
}

extension IDBCommandExecutor: AccessibilityDescribing {}

struct AccessibilityInfoMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_AccessibilityInfoRequest, context: ServerContext) async throws -> Idb_AccessibilityInfoResponse {
    try await Self.respond(to: request, using: commandExecutor, cancellation: context.cancellation)
  }

  /// Lifted out of `handle` so it can be tested without a `ServerContext`. `cancellation` is the RPC's.
  static func respond(
    to request: Idb_AccessibilityInfoRequest,
    using commandExecutor: any AccessibilityDescribing,
    cancellation: ServerContext.RPCCancellationHandle? = nil
  ) async throws -> Idb_AccessibilityInfoResponse {
    do {
      guard let cancellation else {
        return try await read(request, using: commandExecutor)
      }
      // The read stops when the client goes away, rather than reading to the end for no one.
      return try await withRPCCancellation(cancellation) {
        try await read(request, using: commandExecutor)
      }
    } catch {
      AccessibilityReadTelemetry.record(failure: error, into: CallTelemetry.current)
      throw error
    }
  }

  private static func read(
    _ request: Idb_AccessibilityInfoRequest,
    using commandExecutor: any AccessibilityDescribing
  ) async throws -> Idb_AccessibilityInfoResponse {
    try AccessibilityInfoRequestTranslation.validate(request)
    let format = AccessibilityInfoRequestTranslation.outputFormat(from: request.format)
    let backend = AccessibilityInfoRequestTranslation.backend(from: request.backend)
    // Built before the branch: both paths are reads of the same tree with the same options, so the
    // marker path honours the request's keys, profiling and frame coverage too.
    let options = try AccessibilityInfoRequestTranslation.options(from: request, format: format)
    // A marker selects a single element to describe; without one the request
    // describes the element at a point, or the whole frontmost app.
    if let query = AccessibilityInfoRequestTranslation.markerQuery(from: request) {
      let response = try await commandExecutor.accessibilityDescribeResponse(query: query, options: options, backend: backend)
      AccessibilityReadTelemetry.record(response, into: CallTelemetry.current)
      let data = try response.formattedOutputJSON(format: options.format)
      return .with {
        $0.json = String(data: data, encoding: .utf8) ?? ""
      }
    }
    let response = try await commandExecutor.accessibilityInfoAtPoint(
      AccessibilityInfoRequestTranslation.point(from: request), options: options, backend: backend)
    AccessibilityReadTelemetry.record(response, into: CallTelemetry.current)
    let jsonData = try AccessibilityInfoRequestTranslation.responseJSON(from: response, format: format)
    return .with {
      $0.json = String(data: jsonData, encoding: .utf8) ?? ""
    }
  }
}

/// How each read went, on the call's own row, whether or not the caller asked for a profile — so a
/// change to how reads are made can be measured across every read rather than the few that profile.
///
/// The element count, durations and backend use the column names the CLI already logs from complete
/// documents, so one query reads both. Translator-backed reads are the only ones that report metrics.
enum AccessibilityReadTelemetry {
  /// A read that failed records how it ended, when the failure says.
  static func record(failure error: Error, into call: CallTelemetry?) {
    guard let call, let outcome = AccessibilityReadOutcome(failure: error) else { return }
    call.setNormal(outcome.rawValue, forKey: "ax_read_outcome")
    if case let AccessibilityError.serviceNotAnswering(_, _, behindAbandoned) = error {
      call.setInt(Int(behindAbandoned), forKey: "ax_requests_behind_abandoned")
    }
  }

  static func record(_ response: AccessibilityElementsResponse, into call: CallTelemetry?) {
    guard let call else { return }
    if let backend = response.backend {
      call.setNormal(backend.rawValue, forKey: "ax_backend")
    }
    guard let metrics = response.translatorMetrics else { return }
    call.setInt(Int(metrics.elementCount), forKey: "ax_element_count")
    call.setInt(Int(metrics.roundTrips), forKey: "ax_round_trips")
    call.setInt(Int(metrics.readDuration * 1000), forKey: "ax_profile_read_ms")
    call.setInt(Int(metrics.totalDuration * 1000), forKey: "ax_profile_total_ms")
    call.setNormal(metrics.translatorReads.rawValue, forKey: "ax_translator_reads")
    call.setNormal(metrics.transport.rawValue, forKey: "ax_transport")
    call.setNormal(metrics.outcome.rawValue, forKey: "ax_read_outcome")
    call.setInt(Int(metrics.acquireDuration * 1000), forKey: "ax_profile_acquire_ms")
    call.setInt(Int(metrics.springBoardCheckDuration * 1000), forKey: "ax_springboard_check_ms")
    call.setInt(Int(metrics.acquireRoundTrips), forKey: "ax_acquire_round_trips")
    call.setInt(Int(metrics.unansweredRequests), forKey: "ax_request_timeouts")
    call.setInt(Int(metrics.requestsBehindAbandoned), forKey: "ax_requests_behind_abandoned")
    if let slowest = metrics.slowestRequest {
      call.setInt(Int(slowest.duration * 1000), forKey: "ax_slowest_request_ms")
      call.setNormal(slowest.kindName, forKey: "ax_slowest_request_type")
    }
  }
}
