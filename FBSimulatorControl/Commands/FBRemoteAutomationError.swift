/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors from the `testmanagerd` remote-automation backend. A Swift enum (mirroring
/// `FBAccessibilityError`) so callers can pattern-match — e.g. `.elementNotFound` lets a wait poll
/// distinguish "not there yet" from a genuine failure — rather than inspecting a stringly error.
public enum FBRemoteAutomationError: LocalizedError, Sendable {
  /// No element in the frontmost tree matched the marker `value` for `key`.
  case elementNotFound(key: String, value: String)
  /// A verb that requires a marker target was given a point or the frontmost application.
  case markerRequired(operation: String)
  /// A verb that requires a point or marker target was given the frontmost application.
  case pointOrMarkerRequired(operation: String)
  /// A verb not yet implemented over remote automation; the accessibility backend serves it.
  case operationUnsupported(operation: String)
  /// The wait for a marker element timed out.
  case timedOut(key: String, value: String, timeout: TimeInterval)
  /// The frontmost application's element tree could not be read at the probe point.
  case treeUnavailable(x: Double, y: Double)
  /// No element was found at the requested point.
  case noElementAtPoint(x: Double, y: Double)
  /// The remote-automation channel is not advertised on this simulator (needs iOS 27+ / Xcode 27).
  case unavailable(underlying: String)
  /// A synthesized input event carried no touch steps.
  case eventMissingTouchSteps
  /// A by-pid application read returned no tree — the pid is not a live app, or its accessibility
  /// server has not started.
  case applicationUnavailable(pid: pid_t)

  public var errorDescription: String? {
    switch self {
    case let .elementNotFound(key, value):
      return "Remote automation found no element matching \(key)=\"\(value)\""
    case let .markerRequired(operation):
      return "\(operation) requires a marker target, not a point or the frontmost application"
    case let .pointOrMarkerRequired(operation):
      return "\(operation) requires a point or marker target, not the frontmost application"
    case let .operationUnsupported(operation):
      return "\(operation) over the testmanagerd remote-automation backend is not yet supported; use --api ax"
    case let .timedOut(key, value, timeout):
      return "Remote automation timed out after \(timeout)s waiting for \(key)=\"\(value)\". \(FBAXTreeSerialization.accessibilityHint)"
    case let .treeUnavailable(x, y):
      return "Remote automation could not read the frontmost application tree at (\(x), \(y)). \(FBAXTreeSerialization.accessibilityHint)"
    case let .noElementAtPoint(x, y):
      return "Remote automation found no element at (\(x), \(y)). \(FBAXTreeSerialization.accessibilityHint)"
    case let .unavailable(underlying):
      return "Remote automation is unavailable on this simulator: testmanagerd is not advertising its remote-automation listener (\(remoteAutomationSockEnvKey)). This requires a simulator runtime whose testmanagerd exposes the remote-automation channel (iOS 27+ / Xcode 27). Underlying error: \(underlying)"
    case .eventMissingTouchSteps:
      return "Remote-automation event contained no touch steps"
    case let .applicationUnavailable(pid):
      return "Remote automation could not read the application with pid \(pid): it is not a running app, or its accessibility server has not started. \(FBAXTreeSerialization.accessibilityHint)"
    }
  }
}

extension FBRemoteAutomationError: CustomStringConvertible {
  public var description: String { errorDescription ?? "FBRemoteAutomationError" }
}
