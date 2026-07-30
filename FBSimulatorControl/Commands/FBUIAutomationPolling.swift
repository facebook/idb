/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Backend-neutral polling helper for the `FBUIAutomation` `wait` verbs. Kept out of either backend
/// so the accessibility and remote-automation conformers depend on shared code rather than on each
/// other.
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
}
