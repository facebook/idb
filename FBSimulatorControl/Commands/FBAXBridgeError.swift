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
/// The cases mirror the guest's `FBAXWire.ErrorKind` vocabulary, because the guest is the only thing that
/// knows which of them happened. Two of them — an application with no accessibility server, and one that
/// did not answer — are facts about the application rather than the transport, so they exist here only
/// long enough for the conformer to re-raise them as the neutral cases.
public enum FBAXBridgeError: LocalizedError, Sendable {
  /// The bundled `SimulatorFrameworkBridge` guest binary could not be located in Resources.
  case bridgeUnavailable
  /// The guest could not bind the private frameworks it reads through, so it can serve no request at all.
  /// The message is the guest's own and names what was missing plus any signature that has drifted beside
  /// it. Its own case because nothing about the target or its configuration changes the outcome — waiting,
  /// relaunching, or enabling accessibility all leave it exactly as broken.
  case readerUnavailable(String)
  /// The frontmost-resolution strategy the caller selected could not name an application, for a reason
  /// that is about the strategy rather than about any one application. Carries the method asked for,
  /// because `--frontmost-method` is the caller's choice and the other two may well answer.
  case frontmostUnresolved(method: FBAXBridgeFrontmostMethod, reason: String)
  /// The guest reported that `pid` names no readable application — a dead pid, or an app whose
  /// accessibility server never started. Its own case (rather than a `guestFailure` string) so the
  /// conformer can re-raise the backend-neutral `FBUIAutomationError.applicationUnavailable` for it,
  /// matching what the remote backend throws for the same condition. `pid` is nil when the guest resolved
  /// nothing to name it — a display-wide hit-test that nothing answered.
  case applicationUnavailable(pid: pid_t?)
  /// The application has an accessibility server and it did not answer in time. Distinct from
  /// `applicationUnavailable` because the application has not gone away, and distinct from an empty
  /// result because it is not an answer at all.
  case applicationNotResponding(pid: pid_t?)
  /// A write carried an assertion about the element at its point and the guest found something else
  /// there, so nothing was written. Its own case so the conformer can re-raise it as the neutral
  /// `FBUIAutomationError.elementMoved` naming the query, which is the part the guest cannot know.
  case assertionFailed(String)
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
      return "The axbridge guest asked the application \(Self.pidPhrase(pid)) for accessibility and it did not answer in time"
    case let .assertionFailed(message):
      return "The axbridge guest refused the write: \(message)"
    case let .guestFailure(message):
      return "The axbridge guest reader failed: \(message)"
    }
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
  ///
  /// A predicate rather than a `switch` inside the poll closure, because the closure needs a live
  /// simulator to reach and this decision is the part worth testing.
  var isTransientDuringMarkerWait: Bool {
    switch self {
    case .frontmostUnresolved, .guestFailure, .applicationUnavailable, .applicationNotResponding:
      return true
    // Nothing about the target makes a reader that cannot bind bind, so both of these are the same on
    // the last poll as on the first. A refused write cannot arise here at all — a poll only reads — and
    // waiting would not make one land, so it is not something to poll through either.
    case .bridgeUnavailable, .readerUnavailable, .assertionFailed:
      return false
    }
  }
}
