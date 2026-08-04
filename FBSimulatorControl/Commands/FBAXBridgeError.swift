/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Failures specific to the `axbridge` transport — getting a guest reader running and talking to it.
/// Failures of the *query* (no such element, empty point, timeout, unsupported verb) are backend-
/// neutral and raised as `FBUIAutomationError`, so a caller can handle them without knowing which
/// backend it holds.
public enum FBAXBridgeError: LocalizedError, Sendable {
  /// The bundled `SimulatorFrameworkBridge` guest binary could not be located in Resources.
  case bridgeUnavailable
  /// The frontmost application's pid could not be resolved via the accessibility path.
  case frontmostUnavailable
  /// The guest binary exited non-zero, produced unparseable output, or reported a read failure.
  case guestFailure(String)
  /// The guest reported that `pid` names no readable application — a dead pid, or an app whose
  /// accessibility server never started. Its own case (rather than a `guestFailure` string) so the
  /// conformer can re-raise the backend-neutral `FBUIAutomationError.applicationUnavailable` for it,
  /// matching what the remote backend throws for the same condition.
  case applicationUnavailable(pid: pid_t)

  public var errorDescription: String? {
    switch self {
    case .bridgeUnavailable:
      return "The SimulatorFrameworkBridge guest binary was not found in the companion Resources directory"
    case .frontmostUnavailable:
      return "axbridge could not resolve the frontmost application's pid. \(FBAXTreeWalk.accessibilityHint)"
    case let .guestFailure(message):
      return "The axbridge guest reader failed: \(message)"
    case let .applicationUnavailable(pid):
      return "The axbridge guest found no readable application for pid \(pid)"
    }
  }
}

extension FBAXBridgeError: CustomStringConvertible {
  public var description: String { errorDescription ?? "FBAXBridgeError" }
}
