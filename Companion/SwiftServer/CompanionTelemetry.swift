/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
@preconcurrency import FBControlCore
import Foundation

/// Per-RPC telemetry replacement for the legacy `FBLoggingWrapper`.
///
/// Applied at the `CompanionServiceProvider` layer. Each RPC method wraps
/// its handler dispatch in one of `unaryCall`, `clientStreaming`,
/// `serverStreaming`, or `bidiStreaming`. The resulting log lines and
/// `FBEventReporter` events are equivalent to what `FBLoggingWrapper`
/// produced when wrapping `FBIDBCommandExecutor` in the ObjC era:
///
/// - `<method> called with: [<args>]` at info on the FBControlCoreLogger
///   (which routes to stderr and the optional log file).
/// - `<method> succeeded` at debug on success, or
///   `<method> failed with: <localizedDescription>` at debug on failure.
/// - One `FBEventReporterSubject(forSuccessfulCall:duration:size:arguments:)`
///   on success (or `(forFailingCall:…)` on failure) reported to the
///   `FBEventReporter`, which routes to scuba via the perfpipe_idb scribe
///   category.
///
/// The arguments list is rendered from the typed gRPC `Request` body via
/// `Mirror`, with each top-level field rendered as `name=value` and the
/// value truncated to 100 characters -- the same cap
/// `FBLoggingWrapper.descriptionForArgumentAtIndex:` enforced on each
/// stringified ObjC argument.
///
/// `size` is always `nil`. The legacy `FBLoggingWrapper` populated it
/// only when the first ObjC method argument implemented a
/// `bytesTransferred` selector -- in practice, none of the proto request
/// types do, so the legacy size was already `nil` for every gRPC method
/// running through the wrapper. Stream-level byte counting would be a
/// genuine enhancement on top of the wrapper's behaviour, but is out of
/// scope for matching it.
struct CompanionTelemetry {

  let logger: FBIDBLogger
  let reporter: FBEventReporter

  /// Match `FBLoggingWrapper.descriptionForArgumentAtIndex:`'s 100-char cap.
  private static let argumentValueLimit = 100

  // MARK: - RPC shapes

  @discardableResult
  func unaryCall<Request, Response>(
    _ method: String,
    request: Request,
    body: () async throws -> Response
  ) async throws -> Response {
    return try await report(method: method, arguments: describeArguments(request), body: body)
  }

  @discardableResult
  func clientStreaming<Response>(
    _ method: String,
    body: () async throws -> Response
  ) async throws -> Response {
    return try await report(method: method, arguments: [], body: body)
  }

  func serverStreaming<Request>(
    _ method: String,
    request: Request,
    body: () async throws -> Void
  ) async throws {
    try await report(method: method, arguments: describeArguments(request), body: body)
  }

  func bidiStreaming(
    _ method: String,
    body: () async throws -> Void
  ) async throws {
    try await report(method: method, arguments: [], body: body)
  }

  // MARK: - Core reporting

  @discardableResult
  private func report<R>(
    method: String,
    arguments: [String],
    body: () async throws -> R
  ) async throws -> R {
    let start = Date()
    logger.info().log("\(method) called with: \(oneLineDescription(arguments))")
    do {
      let result = try await body()
      let duration = Date().timeIntervalSince(start)
      logger.debug().log("\(method) succeeded")
      reporter.report(
        FBEventReporterSubject(
          forSuccessfulCall: method,
          duration: duration,
          size: nil,
          arguments: arguments))
      return result
    } catch {
      let duration = Date().timeIntervalSince(start)
      let message = (error as NSError).localizedDescription
      logger.debug().log("\(method) failed with: \(message)")
      reporter.report(
        FBEventReporterSubject(
          forFailingCall: method,
          duration: duration,
          message: message,
          size: nil,
          arguments: arguments))
      throw error
    }
  }

  // MARK: - Argument description (Mirror-based, mirrors FBLoggingWrapper's intent)

  private func describeArguments(_ request: Any) -> [String] {
    let mirror = Mirror(reflecting: request)
    var args: [String] = []
    for child in mirror.children {
      guard var label = child.label else { continue }
      // SwiftProtobuf prefixes backing-storage fields with "_"; surface the user-facing name.
      if label.hasPrefix("_") {
        label = String(label.dropFirst())
      }
      let raw = "\(child.value)"
      let truncated =
        raw.count > Self.argumentValueLimit
        ? String(raw.prefix(Self.argumentValueLimit)) + "..."
        : raw
      args.append("\(label)=\(truncated)")
    }
    return args
  }

  private func oneLineDescription(_ arguments: [String]) -> String {
    "[" + arguments.joined(separator: ", ") + "]"
  }
}
