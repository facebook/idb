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
/// - `<method> succeeded in <duration>` at info on success, or
///   `<method> failed after <duration>: <localizedDescription>` at info on
///   failure. Completion stays at info (rather than debug) so a failing call
///   is visible even when debug logging is disabled via `-log-level info`.
/// - One `FBEventReporterSubject(forSuccessfulCall:duration:size:arguments:)`
///   on success (or `(forFailingCall:…)` on failure) reported to the
///   `FBEventReporter`, which routes to scuba via the perfpipe_idb scribe
///   category.
///
/// The arguments list is rendered from the typed gRPC `Request` body via
/// `Mirror`, with each top-level field rendered as `name=value` and the
/// value truncated to 100 characters -- the same cap
/// `FBLoggingWrapper.descriptionForArgumentAtIndex:` enforced on each
/// stringified ObjC argument. Unlike the legacy pure-prefix cut, truncation
/// keeps both ends: container GUIDs and temp paths differ at the tail, which
/// a prefix cut discards. Empty protobuf `unknownFields` are omitted: they
/// are present on every request and carry no information when empty.
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
    // Monotonic on purpose: a wall clock can step backwards (NTP) across the
    // await, producing negative durations.
    let start = DispatchTime.now()
    logger.info().log("\(method) called with: \(oneLineDescription(arguments))")
    do {
      let result = try await body()
      let duration = Self.secondsSince(start)
      logger.info().log("\(method) succeeded in \(Self.formatDuration(duration))")
      reporter.report(
        FBEventReporterSubject(
          forSuccessfulCall: method,
          duration: duration,
          size: nil,
          arguments: arguments))
      return result
    } catch {
      let duration = Self.secondsSince(start)
      let message = (error as NSError).localizedDescription
      logger.info().log("\(method) failed after \(Self.formatDuration(duration)): \(message)")
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

  private static func secondsSince(_ start: DispatchTime) -> TimeInterval {
    TimeInterval(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
  }

  /// Renders a call duration for the completion line: whole milliseconds
  /// below one second, two-decimal seconds above it.
  static func formatDuration(_ duration: TimeInterval) -> String {
    if duration < 1 {
      return String(format: "%.0fms", duration * 1000)
    }
    return String(format: "%.2fs", duration)
  }

  /// Truncates over-long values to exactly `limit` characters, keeping the
  /// head and the tail around an ellipsis. Values at or under the limit
  /// pass through verbatim.
  static func truncateMiddle(_ value: String, limit: Int) -> String {
    guard value.count > limit else {
      return value
    }
    let ellipsis = "..."
    let headCount = (limit - ellipsis.count) / 2
    let tailCount = limit - ellipsis.count - headCount
    return String(value.prefix(headCount)) + ellipsis + String(value.suffix(tailCount))
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
      // Every protobuf request carries unknownFields; skip the storage when
      // it is empty so the log line only names fields that say something.
      // Non-empty storage is kept verbatim for forward-compat debugging.
      if label == "unknownFields" && raw == "UnknownStorage(data: 0 bytes)" {
        continue
      }
      // Protobuf messages render across lines (e.g. a file container dumps
      // as `...Container:\nkind: ROOT\n)]`); flatten so one argument stays
      // on one log line and line-oriented tools keep working.
      let singleLine =
        raw
        .components(separatedBy: .newlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      args.append("\(label)=\(Self.truncateMiddle(singleLine, limit: Self.argumentValueLimit))")
    }
    return args
  }

  private func oneLineDescription(_ arguments: [String]) -> String {
    "[" + arguments.joined(separator: ", ") + "]"
  }
}
