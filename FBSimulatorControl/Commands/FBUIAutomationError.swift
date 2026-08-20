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
///
/// A case appends remediation only where that remedy plausibly applies to it. `applicationUnavailable`
/// is the one condition `ApplicationAccessibilityEnabled` addresses; a point that is empty and a marker
/// that never appeared are not accessibility-configuration problems, and telling a reader they might be
/// is what makes the advice ignorable on the case where it is right.
public enum FBUIAutomationError: LocalizedError, Sendable {
  /// No element matched the marker `value` for `key`.
  case elementNotFound(backend: FBUIAutomationBackend, key: String, value: String)
  /// A marker matched an element, but it reports no on-screen frame — off-screen or still settling —
  /// so there is no point to interact with. Distinct from `elementNotFound`: the element exists.
  case elementNotOnScreen(backend: FBUIAutomationBackend, key: String, value: String)
  /// A read answered without geometry: no element, or an element carrying no frame. Distinct from
  /// `elementNotOnScreen`, which is about an element whose frame puts it out of reach — here there is no
  /// frame to judge. It names whichever target shape was asked, because a frame can be read of a whole
  /// tree as well as of a marker.
  case frameUnavailable(backend: FBUIAutomationBackend, query: FBAccessibilityElementQuery)
  /// No element sits at the requested point. A successful read of empty space, raised as an error only
  /// because `describe(.point:)` has to answer with an element — so it carries no remediation, there
  /// being nothing wrong to remedy.
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
  /// A read found no tree: the pid is not a live app, or its accessibility server never started. `pid` is
  /// nil when the read resolved no application to name — a point read that nothing answered.
  case applicationUnavailable(backend: FBUIAutomationBackend, pid: pid_t?)
  /// The application has an accessibility server and did not answer in time. A fact about the
  /// application rather than the transport, like `applicationUnavailable`, and held apart from it because
  /// the application has not gone away — so it is a wait, not a reconfiguration.
  case applicationNotResponding(backend: FBUIAutomationBackend, pid: pid_t?)
  /// A `tap` asserted the element's value for `key` (via `FBTapOptions.assertion`) before tapping, but
  /// the element's actual value did not match.
  case valueMismatch(backend: FBUIAutomationBackend, key: String, expected: String, actual: String)
  /// A write resolved its target by reading a tree and then acted on the point that element occupied,
  /// and by the time it landed the element there was no longer the one the query named. Distinct from
  /// `elementNotFound`, which is a marker that matched nothing at all: this one matched, and then the
  /// screen moved out from under it.
  case elementMoved(backend: FBUIAutomationBackend, key: String, value: String)

  public var errorDescription: String? {
    switch self {
    case let .elementNotFound(backend, key, value):
      return "\(backend.displayName) found no element whose \(key) contains \"\(value)\""
    case let .elementNotOnScreen(backend, key, value):
      return "\(backend.displayName) matched an element whose \(key) contains \"\(value)\", but it is off-screen and has no frame to interact with"
    case let .frameUnavailable(backend, query):
      return "\(backend.displayName) read \(query), but the read carried no frame to report"
    case let .noElementAtPoint(backend, x, y):
      return "\(backend.displayName) found no element at (\(x), \(y)); the point is empty"
    case let .timedOut(backend, key, value, timeout):
      return "\(backend.displayName) timed out after \(timeout)s waiting for \(key) containing \"\(value)\"; it never appeared. Describe the tree to see what is on screen"
    case let .markerRequired(_, operation):
      return "\(operation) requires a marker target, not a point or a whole-tree query"
    case let .pointOrMarkerRequired(_, operation):
      return "\(operation) requires a point or marker target, not a whole-tree query"
    case let .invalidPollInterval(backend, pollInterval):
      return "\(backend.displayName) was given a negative poll interval (\(pollInterval)s); it must be zero or positive"
    case let .operationUnsupported(backend, operation):
      return "\(operation) is not supported over \(backend.inlineName)"
    case let .applicationUnavailable(backend, pid):
      return "\(backend.displayName) could not read the application \(Self.pidPhrase(pid)): it is not a running app, or its accessibility server has not started. \(FBAccessibilityGuidance.accessibilityServer)"
    case let .applicationNotResponding(backend, pid):
      return "\(backend.displayName) asked the application \(Self.pidPhrase(pid)) for accessibility and it did not answer in time"
    case let .valueMismatch(backend, key, expected, actual):
      return "\(backend.displayName) expected \(key) to equal \"\(expected)\" before tapping, but it was \"\(actual)\""
    case let .elementMoved(backend, key, value):
      return "\(backend.displayName) resolved \(key) containing \"\(value)\" and the element had moved by the time the write reached it; nothing was written. Read the tree again and retry"
    }
  }

  /// How a message refers to the application it is about. A read that resolved nothing has no pid to
  /// print, and saying where it looked beats printing a zero.
  private static func pidPhrase(_ pid: pid_t?) -> String {
    guard let pid else {
      return "at that point"
    }
    return "with pid \(pid)"
  }
}

extension FBUIAutomationError: CustomStringConvertible {
  public var description: String { errorDescription ?? "FBUIAutomationError" }
}

public extension FBUIAutomationBackend {
  /// How this backend names itself part-way through a sentence, rather than at the start of one.
  ///
  /// `displayName` leads with a capitalised "The" because nearly every message opens with it. A message
  /// that names the backend mid-sentence needs the article in lower case, and needs not to append a
  /// second "backend" to a phrase that already ends in one.
  var inlineName: String {
    let name = displayName
    return name.prefix(1).lowercased() + name.dropFirst()
  }

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
