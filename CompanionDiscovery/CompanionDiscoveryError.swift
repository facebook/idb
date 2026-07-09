/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors raised while discovering or starting companions.
public enum CompanionDiscoveryError: Error, CustomStringConvertible {
  /// The registry lockfile could not be acquired within the timeout.
  case lockTimedOut(path: String)
  /// The registry lockfile could not be created for an unexpected reason.
  case lockFailed(path: String, code: Int32)
  /// The companion process could not be launched.
  case spawnFailed(reason: String)
  /// The companion launched but did not report a usable address on stdout.
  case companionNotReady(reason: String)
  /// The companion bound a domain socket path different from the requested one.
  case socketPathMismatch(expected: String, actual: String)
  /// More than one companion is running, so one could not be chosen without a udid.
  case multipleCompanions(udids: [String])

  public var description: String {
    switch self {
    case let .lockTimedOut(path):
      return "Timed out acquiring the companion registry lock at \(path)"
    case let .lockFailed(path, code):
      return "Failed to acquire the companion registry lock at \(path) (errno \(code))"
    case let .spawnFailed(reason):
      return "Failed to spawn companion: \(reason)"
    case let .companionNotReady(reason):
      return "Companion did not become ready: \(reason)"
    case let .socketPathMismatch(expected, actual):
      return "Companion bound an unexpected domain socket (expected \(expected), got \(actual))"
    case let .multipleCompanions(udids):
      return "Multiple companions are running (\(udids.joined(separator: ", "))); pass a udid to choose one"
    }
  }
}
