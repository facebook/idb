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
///
/// The cases mirror the guest's `FBAXWire.ErrorKind`. The two application-level ones are re-raised by
/// the conformer as the backend-neutral `FBUIAutomationError` cases.
public enum FBAXBridgeError: LocalizedError, Sendable {
  /// The bundled `SimulatorFrameworkBridge` guest binary could not be located in Resources.
  case bridgeUnavailable
  /// The guest could not bind the private frameworks it reads through, so it can serve no request. The
  /// message is the guest's own. Never transient: no target configuration change fixes it.
  case readerUnavailable(String)
  /// The frontmost-resolution strategy the caller selected could not name an application, for a reason
  /// that is about the strategy rather than about any one application. Carries the method asked for,
  /// because `--frontmost-method` is the caller's choice and the other two may well answer.
  case frontmostUnresolved(method: FBAXBridgeFrontmostMethod, reason: String)
  /// The guest reported that `pid` names no readable application — a dead pid, or an app whose
  /// accessibility server never started. `pid` is nil when a display-wide hit-test resolves nothing.
  case applicationUnavailable(pid: pid_t?)
  /// The application has an accessibility server and it did not answer in time. Distinct from
  /// `applicationUnavailable` because the application has not gone away, and distinct from an empty
  /// result because it is not an answer at all.
  case applicationNotResponding(pid: pid_t?)
  /// A write carried an assertion about the element at its point and the guest found something else
  /// there, so nothing was written.
  case assertionFailed(String)
  /// The socket path is longer than `sockaddr_un.sun_path` can hold, so no guest can ever be reached at
  /// it.
  case socketPathTooLong(path: String, limit: Int)
  /// The guest this host spawned terminated before binding its serve socket. Carries the exit as data:
  /// a signal before `main` means it could not load at all.
  case guestDiedBeforeBinding(pid: pid_t, signal: Int?, exitCode: Int?, path: String)
  /// The guest binary exited non-zero, produced unparseable output, or reported a failure with nothing
  /// further to say about it. Also where a failure kind this host does not recognize lands.
  case guestFailure(String)

  public var errorDescription: String? {
    switch self {
    case .bridgeUnavailable:
      return "The SimulatorFrameworkBridge guest binary was not found in the companion Resources directory"
    case let .readerUnavailable(message):
      return "The axbridge guest reader could not bind the simulator's accessibility runtime: \(message)"
    case let .frontmostUnresolved(method, reason):
      return "axbridge could not resolve the frontmost application using the \(method.rawValue) strategy: \(reason)"
    case let .applicationUnavailable(pid):
      return "The axbridge guest found no readable application \(Self.pidPhrase(pid))"
    case let .applicationNotResponding(pid):
      return "The axbridge guest requested accessibility from the application \(Self.pidPhrase(pid)), which did not answer in time"
    case let .assertionFailed(message):
      return "The axbridge guest refused the write: \(message)"
    case let .socketPathTooLong(path, limit):
      return "The axbridge serve socket path is \(path.utf8.count) bytes, over the \(limit)-byte sockaddr_un limit, so no guest can be reached at it: \(path)"
    case let .guestDiedBeforeBinding(pid, signal, exitCode, path):
      return "The axbridge guest (pid \(pid)) \(Self.exitPhrase(signal: signal, exitCode: exitCode)) before binding its serve socket at \(path)"
    case let .guestFailure(message):
      return "The axbridge guest reader failed: \(message)"
    }
  }

  /// A clause, not a sentence: the caller has already named the process it is about.
  ///
  /// Signal zero is not a signal, matching `FBAXBridgeConnection.socketClosedMessage`.
  private static func exitPhrase(signal: Int?, exitCode: Int?) -> String {
    if let signal, signal != 0 {
      return "was killed by signal \(signal)"
    }
    if let exitCode {
      return "exited with code \(exitCode)"
    }
    return "is gone, with no exit status recorded"
  }

  /// How a message refers to the process it is about. A display-wide read resolved nothing, so there is
  /// no pid to print and saying so beats printing a zero.
  private static func pidPhrase(_ pid: pid_t?) -> String {
    guard let pid else {
      return "at that point"
    }
    return "with pid \(pid)"
  }
}

extension FBAXBridgeError: CustomStringConvertible {
  public var description: String { errorDescription ?? "FBAXBridgeError" }
}

extension FBAXBridgeError {

  /// Whether a read failure met while polling for a marker is worth polling through.
  ///
  /// A wait is for something that has not happened *yet*, so a failure is worth swallowing only when
  /// waiting could plausibly change it. An app still launching has no frontmost, no readable tree and no
  /// accessibility server, and acquires all three shortly — so all of those are "not there yet" and the
  /// poll continues. A failure of the reader or its plumbing is not that: it answers the same way on
  /// every poll, and swallowing it spends the caller's whole timeout only to report a timeout, hiding
  /// the diagnosis the failure already carried.
  var isTransientDuringMarkerWait: Bool {
    switch self {
    case .frontmostUnresolved, .guestFailure, .applicationUnavailable, .applicationNotResponding:
      return true
    // None of these change between polls: the reader cannot bind, the path is too long, the guest cannot
    // start, and a poll never writes.
    case .bridgeUnavailable, .readerUnavailable, .assertionFailed, .socketPathTooLong, .guestDiedBeforeBinding:
      return false
    }
  }
}
