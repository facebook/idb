/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A failure of a UI-automation *query*, raised the same way by every backend.
///
/// `FBUIAutomation` is a protocol, so a caller holding one does not statically know which backend is
/// serving it. These conditions — the element isn't there, the point is empty, the wait elapsed, the
/// target shape is wrong for the verb, the backend doesn't implement it — are facts about the query,
/// not about a transport, so they are one type with a `backend` tag rather than one enum per backend.
/// That is what lets `catch FBUIAutomationError.elementNotFound` work regardless of the backend in
/// hand. Failures that genuinely belong to one transport (a missing guest binary, an unadvertised
/// daemon, a dead accessibility dispatcher) stay in that backend's own error type.
public enum FBUIAutomationError: LocalizedError, Sendable {
  /// No element matched the marker `value` for `key`.
  case elementNotFound(backend: FBUIAutomationBackend, key: String, value: String)
  /// A marker matched an element, but it reports no on-screen frame — off-screen or still settling —
  /// so there is no point to interact with. Distinct from `elementNotFound`: the element exists.
  case elementNotOnScreen(backend: FBUIAutomationBackend, key: String, value: String)
  /// No element sits at the requested point.
  case noElementAtPoint(backend: FBUIAutomationBackend, x: Double, y: Double)
  /// The wait for a marker element elapsed.
  case timedOut(backend: FBUIAutomationBackend, key: String, value: String, timeout: TimeInterval)
  /// A verb that requires a marker target was given a point or a whole-tree query.
  case markerRequired(backend: FBUIAutomationBackend, operation: String)
  /// A verb that requires a point or marker target was given a whole-tree query.
  case pointOrMarkerRequired(backend: FBUIAutomationBackend, operation: String)
  /// A wait was given a negative poll interval, which has no meaning and would trap the sleep timer.
  case invalidPollInterval(backend: FBUIAutomationBackend, pollInterval: TimeInterval)
  /// A verb this backend does not implement.
  case operationUnsupported(backend: FBUIAutomationBackend, operation: String)
  /// A by-pid read found no tree: the pid is not a live app, or its accessibility server never started.
  case applicationUnavailable(backend: FBUIAutomationBackend, pid: pid_t)
  /// A `tap` asserted the element's value for `key` (via `FBTapOptions.assertion`) before tapping, but
  /// the element's actual value did not match.
  case valueMismatch(backend: FBUIAutomationBackend, key: String, expected: String, actual: String)

  public var errorDescription: String? {
    switch self {
    case let .elementNotFound(backend, key, value):
      return "\(backend.displayName) found no element whose \(key) contains \"\(value)\""
    case let .elementNotOnScreen(backend, key, value):
      return "\(backend.displayName) matched an element whose \(key) contains \"\(value)\", but it is off-screen and has no frame to interact with"
    case let .noElementAtPoint(backend, x, y):
      return "\(backend.displayName) found no element at (\(x), \(y)). \(FBAXTreeWalk.accessibilityHint)"
    case let .timedOut(backend, key, value, timeout):
      return "\(backend.displayName) timed out after \(timeout)s waiting for \(key) containing \"\(value)\". \(FBAXTreeWalk.accessibilityHint)"
    case let .markerRequired(_, operation):
      return "\(operation) requires a marker target, not a point or a whole-tree query"
    case let .pointOrMarkerRequired(_, operation):
      return "\(operation) requires a point or marker target, not a whole-tree query"
    case let .invalidPollInterval(backend, pollInterval):
      return "\(backend.displayName) was given a negative poll interval (\(pollInterval)s); it must be zero or positive"
    case let .operationUnsupported(backend, operation):
      return "\(operation) is not supported over the \(backend.displayName) backend"
    case let .applicationUnavailable(backend, pid):
      return "\(backend.displayName) could not read the application with pid \(pid): it is not a running app, or its accessibility server has not started. \(FBAXTreeWalk.accessibilityHint)"
    case let .valueMismatch(backend, key, expected, actual):
      return "\(backend.displayName) expected \(key) to equal \"\(expected)\" before tapping, but it was \"\(actual)\""
    }
  }
}

extension FBUIAutomationError: CustomStringConvertible {
  public var description: String { errorDescription ?? "FBUIAutomationError" }
}

public extension FBUIAutomationBackend {
  /// How this backend names itself in an error a user reads.
  var displayName: String {
    switch self {
    case .accessibility:
      return "The accessibility backend"
    case .remoteAutomation:
      return "The testmanagerd remote-automation backend"
    case .axBridge:
      return "The axbridge backend"
    }
  }
}
