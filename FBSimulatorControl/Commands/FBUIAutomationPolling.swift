/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Polling shared by the accessibility and axbridge `wait` implementations.
enum FBUIAutomationPolling {

  /// Polls `probe` until it returns a non-nil value or `timeout` elapses (measured by `clock`),
  /// sleeping `pollInterval` between attempts. `clock`/`sleep` are injected for deterministic tests.
  static func pollUntilFound<T>(
    timeout: TimeInterval,
    pollInterval: TimeInterval,
    clock: () -> TimeInterval,
    sleep: (TimeInterval) async throws -> Void,
    probe: () async throws -> T?
  ) async throws -> T? {
    let deadline = clock() + timeout
    while true {
      if let value = try await probe() {
        return value
      }
      if clock() >= deadline {
        return nil
      }
      try await sleep(pollInterval)
    }
  }

  /// The whole `wait` verb, for a backend that can answer "is the marker there yet?".
  ///
  /// `probe` returns `true` once the element is present and `nil` while it is not yet — a probe should
  /// treat "not there" as `nil` rather than throwing, and throw only on a genuine failure, which ends
  /// the wait immediately instead of burning the timeout.
  static func waitForMarker(
    _ query: FBAccessibilityElementQuery,
    backend: FBUIAutomationBackend,
    timeout: TimeInterval,
    pollInterval: TimeInterval,
    probe: (_ value: String, _ key: FBAXSearchableKey, _ depth: UInt) async throws -> Bool?
  ) async throws {
    guard case let .marker(value, key, depth, _) = query else {
      throw FBUIAutomationError.markerRequired(backend: backend, operation: "Waiting")
    }
    // A negative interval would trap `Task.sleep`'s unsigned conversion below; reject it loudly rather
    // than crash the process on nonsensical input.
    guard pollInterval >= 0 else {
      throw FBUIAutomationError.invalidPollInterval(backend: backend, pollInterval: pollInterval)
    }
    let found = try await pollUntilFound(
      timeout: timeout,
      pollInterval: pollInterval,
      clock: { Date().timeIntervalSinceReferenceDate },
      sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
      try await probe(value, key, depth)
    }
    if found == nil {
      throw FBUIAutomationError.timedOut(backend: backend, key: key.rawValue, value: value, timeout: timeout)
    }
  }
}
