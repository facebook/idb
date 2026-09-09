/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// How a process ended: a normal exit with a code, or death by signal.
///
/// Exactly one case holds for any finished process. This replaces the
/// `statLoc`/`exitCode`/`signal` future triple, where the two specific
/// futures resolved such that awaiting the one that did not happen threw.
public enum TerminationStatus: Sendable, Equatable {
  case exited(Int32)
  case signalled(Int32)

  /// Decodes a raw `wait(2)` status word.
  ///
  /// Reproduces the decode in `FBProcessSpawnCommandHelpers` exactly,
  /// including its treatment of a stopped status (low bits `0x7f`) as an
  /// exit — the engine only ever delivers statuses for processes that have
  /// terminated, so a stopped status cannot occur in practice.
  public init(statLoc: Int32) {
    let wstatus = statLoc & 0x7f // _WSTATUS
    if wstatus != 0x7f /* _WSTOPPED */ && wstatus != 0 {
      self = .signalled(wstatus) // WTERMSIG
    } else {
      self = .exited((statLoc >> 8) & 0xff) // WEXITSTATUS
    }
  }
}

/// Which terminations a run-to-completion call treats as success.
public enum ExitPolicy: Sendable, Equatable {
  /// Only a normal exit with code zero.
  case mustExitZero
  /// Only a normal exit with one of these codes.
  case mustExit(Set<Int32>)
  /// Any termination, including death by signal.
  case any

  /// Whether `status` satisfies this policy.
  public func accepts(_ status: TerminationStatus) -> Bool {
    switch self {
    case .mustExitZero:
      return status == .exited(0)
    case .mustExit(let codes):
      guard case .exited(let code) = status else {
        return false
      }
      return codes.contains(code)
    case .any:
      return true
    }
  }
}
