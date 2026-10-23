/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The stages a launch goes through before the app is running, each reported as a column of whole
/// milliseconds on the call's event.
enum LaunchStage: String, CaseIterable {
  /// Preparing the app's environment for microphone injection.
  case audioInjection = "audio_injection_ms"
  /// Replacing storage and target placeholders in the app's environment.
  case environmentReplacement = "env_replace_ms"
  /// The target's launch, from its checks of the app through the app running.
  case launch = "launch_ms"

  /// Runs `body` and records how long it took, whether it returned or threw.
  func measure<T>(
    into call: CallTelemetry?,
    now: () -> ContinuousClock.Instant = { ContinuousClock.now },
    _ body: () async throws -> T
  ) async rethrows -> T {
    let start = now()
    defer {
      call?.setInt(Self.wholeMilliseconds(start.duration(to: now())), forKey: rawValue)
    }
    return try await body()
  }

  static func wholeMilliseconds(_ duration: Duration) -> Int {
    let (seconds, attoseconds) = duration.components
    return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
  }
}
