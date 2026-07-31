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

  public var errorDescription: String? {
    switch self {
    case .bridgeUnavailable:
      return "The SimulatorFrameworkBridge guest binary was not found in the companion Resources directory"
    case .frontmostUnavailable:
      return "axbridge could not resolve the frontmost application's pid. \(FBAXTreeSerialization.accessibilityHint)"
    case let .guestFailure(message):
      return "The axbridge guest reader failed: \(message)"
    }
  }
}

extension FBAXBridgeError: CustomStringConvertible {
  public var description: String { errorDescription ?? "FBAXBridgeError" }
}
