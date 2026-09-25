/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Polling shared by the accessibility and axbridge `wait` implementations.
enum UIAutomationPolling {

  /// Polls `probe` until it returns a match or `timeout` elapses (measured by `clock`),
  /// sleeping `pollInterval` between attempts. `clock`/`sleep` are injected for deterministic tests.
  static func pollUntilFound<T>(
    timeout: TimeInterval,
    pollInterval: TimeInterval,
    clock: () -> TimeInterval,
    sleep: (TimeInterval) async throws -> Void,
    probe: () async throws -> AccessibilitySearchResult<T>
  ) async throws -> AccessibilitySearchResult<T> {
    let deadline = clock() + timeout
    while true {
      let result = try await probe()
      if result.match != nil || clock() >= deadline {
        return result
      }
      try await sleep(pollInterval)
    }
  }

  /// The whole `wait` verb, for a backend that can answer "is the marker there yet?".
  ///
  /// A probe returns a match once the element is present and diagnostics for an unsuccessful read.
  /// Terminal failures throw immediately; retryable failures belong to the probe's diagnostics.
  static func waitForMarker(
    _ query: AccessibilityElementQuery,
    backend: UIAutomationBackend,
    timeout: TimeInterval,
    pollInterval: TimeInterval,
    probe: (_ value: String, _ key: AXSearchableKey, _ depth: UInt) async throws -> AccessibilitySearchResult<Bool>
  ) async throws {
    guard case let .marker(value, key, depth, _) = query else {
      throw UIAutomationError.markerRequired(backend: backend, operation: "Waiting")
    }
    // A negative interval would trap `Task.sleep`'s unsigned conversion below; reject it loudly rather
    // than crash the process on nonsensical input.
    guard pollInterval >= 0 else {
      throw UIAutomationError.invalidPollInterval(backend: backend, pollInterval: pollInterval)
    }
    let result = try await pollUntilFound(
      timeout: timeout,
      pollInterval: pollInterval,
      clock: { Date().timeIntervalSinceReferenceDate },
      sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
      try await probe(value, key, depth)
    }
    if result.match == nil {
      throw UIAutomationError.timedOut(
        backend: backend, key: key.rawValue, value: value, timeout: timeout, diagnostics: result.diagnostics)
    }
  }
}
