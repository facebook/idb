/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors from the `axbridge` guest-reader backend. A Swift enum (mirroring `FBRemoteAutomationError`)
/// so callers can pattern-match — e.g. `.elementNotFound` lets a wait poll distinguish "not there
/// yet" from a genuine failure — rather than inspecting a stringly error.
public enum FBAXBridgeError: LocalizedError, Sendable {
  /// The bundled `SimulatorFrameworkBridge` guest binary could not be located in Resources.
  case bridgeUnavailable
  /// The frontmost application's pid could not be resolved via the accessibility path.
  case frontmostUnavailable
  /// A by-pid read returned no tree — the pid is not a live app, or its accessibility server has not
  /// started (see the accessibility hint).
  case applicationUnavailable(pid: pid_t)
  /// The guest binary exited non-zero, produced unparseable output, or reported a read failure.
  case guestFailure(String)
  /// No element in the tree matched the marker `value` for `key`.
  case elementNotFound(key: String, value: String)
  /// No element in the tree contained the requested point.
  case noElementAtPoint(x: Double, y: Double)
  /// A verb that requires a marker target was given a point or a whole-tree query.
  case markerRequired(operation: String)
  /// A verb that requires a point or marker target was given a whole-tree query.
  case pointOrMarkerRequired(operation: String)
  /// A verb not yet implemented over the axbridge backend (element writes land in a later change).
  case operationUnsupported(operation: String)
  /// The wait for a marker element timed out.
  case timedOut(key: String, value: String, timeout: TimeInterval)

  public var errorDescription: String? {
    switch self {
    case .bridgeUnavailable:
      return "The SimulatorFrameworkBridge guest binary was not found in the companion Resources directory"
    case .frontmostUnavailable:
      return "axbridge could not resolve the frontmost application's pid. \(FBSimulatorRemoteAutomation.accessibilityHint)"
    case let .applicationUnavailable(pid):
      return "axbridge could not read the application with pid \(pid): it is not a running app, or its accessibility server has not started. \(FBSimulatorRemoteAutomation.accessibilityHint)"
    case let .guestFailure(message):
      return "The axbridge guest reader failed: \(message)"
    case let .elementNotFound(key, value):
      return "axbridge found no element matching \(key)=\"\(value)\""
    case let .noElementAtPoint(x, y):
      return "axbridge found no element at (\(x), \(y)). \(FBSimulatorRemoteAutomation.accessibilityHint)"
    case let .markerRequired(operation):
      return "\(operation) requires a marker target, not a point or a whole-tree query"
    case let .pointOrMarkerRequired(operation):
      return "\(operation) requires a point or marker target, not a whole-tree query"
    case let .operationUnsupported(operation):
      return "\(operation) over the axbridge backend is not yet supported"
    case let .timedOut(key, value, timeout):
      return "axbridge timed out after \(timeout)s waiting for \(key)=\"\(value)\". \(FBSimulatorRemoteAutomation.accessibilityHint)"
    }
  }
}

extension FBAXBridgeError: CustomStringConvertible {
  public var description: String { errorDescription ?? "FBAXBridgeError" }
}
