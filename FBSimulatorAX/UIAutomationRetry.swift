/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

/// Whether a failed UI automation operation can be sent again as it was, and why.
///
/// idb reports this and does not act on it: whether a retry is worth its time is the caller's decision,
/// but only idb knows what the failed operation did to the application.
public enum UIAutomationRetry: Equatable, Sendable {
  /// Nothing was written to the application, so sending the operation again cannot repeat an effect.
  case nothingWritten
  /// A write may have landed, and sending it again converges on the same state.
  case idempotent
  /// Nothing was written, because the element at the target was not the one the caller named. Read the
  /// screen again before deciding to send it.
  case rereadFirst
  /// A write may have landed, and sending it again may repeat it.
  case outcomeUnknown
  /// Sending the same operation again meets the same failure.
  case willNotChange

  public enum Verdict: String, Sendable {
    case safe
    case safeAfterReread = "safe_after_reread"
    case unsafe
  }

  public enum Reason: String, Sendable {
    case nothingWritten = "nothing_written"
    case idempotent
    case outcomeUnknown = "outcome_unknown"
    case willNotChange = "will_not_change"
  }

  public var verdict: Verdict {
    switch self {
    case .nothingWritten, .idempotent: .safe
    case .rereadFirst: .safeAfterReread
    case .outcomeUnknown, .willNotChange: .unsafe
    }
  }

  public var reason: Reason {
    switch self {
    case .nothingWritten, .rereadFirst: .nothingWritten
    case .idempotent: .idempotent
    case .outcomeUnknown: .outcomeUnknown
    case .willNotChange: .willNotChange
    }
  }

  /// The verdict for an error a UI automation operation threw, or nil when it is not one this module
  /// can judge. Nil means unknown, never safe.
  public init?(for error: any Error) {
    switch error {
    case let error as UIAutomationError:
      self = error.retry
    case let error as AXBridgeError:
      self = error.retry
    default:
      return nil
    }
  }
}

public extension UIAutomationError {
  var retry: UIAutomationRetry {
    switch self {
    // Reads, and writes that failed while finding their target: the screen may yet change.
    case .elementNotFound, .elementNotOnScreen, .frameUnavailable, .noElementAtPoint, .timedOut,
      .applicationUnavailable, .applicationNotResponding:
      return .nothingWritten
    case .valueMismatch, .elementMoved:
      return .rereadFirst
    case let .writeUnconfirmed(_, idempotent, _):
      return idempotent ? .idempotent : .outcomeUnknown
    case .markerRequired, .pointOrMarkerRequired, .invalidPollInterval, .operationUnsupported, .traversalCannotAnswer:
      return .willNotChange
    }
  }
}

public extension AXBridgeError {
  /// A write the guest may have sent is raised as `UIAutomationError.writeUnconfirmed` instead, so every
  /// case here sent nothing.
  var retry: UIAutomationRetry {
    switch self {
    case .frontmostUnresolved, .guestFailure, .applicationUnavailable, .applicationNotResponding:
      return .nothingWritten
    case .assertionFailed:
      return .rereadFirst
    case .bridgeUnavailable, .readerUnavailable, .socketPathTooLong, .guestDiedBeforeBinding:
      return .willNotChange
    }
  }

  /// Whether a read failure met while polling for a marker is worth polling through.
  ///
  /// A wait is for something that has not happened *yet*, so a failure is worth swallowing only when
  /// waiting could plausibly change it. An app still launching has no frontmost, no readable tree and no
  /// accessibility server, and acquires all three shortly — so all of those are "not there yet" and the
  /// poll continues. A failure of the reader or its plumbing is not that: it answers the same way on
  /// every poll, and swallowing it spends the caller's whole timeout only to report a timeout, hiding
  /// the diagnosis the failure already carried.
  internal var isTransientDuringMarkerWait: Bool {
    retry.verdict == .safe
  }
}
