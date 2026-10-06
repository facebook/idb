/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Set as the error on whichever of `exitCode` / `signal` did not happen.
public enum ProcessTerminationError: Error {
  case exitedWithSignal(processIdentifier: pid_t, processName: String, signal: Int32)
  case exitedWithCode(processIdentifier: pid_t, processName: String, exitCode: Int32)
}

extension ProcessTerminationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .exitedWithSignal(processIdentifier, processName, signal):
      return "Process \(processIdentifier) (\(processName)) exited with signal \(signal)"
    case let .exitedWithCode(processIdentifier, processName, exitCode):
      return "Process \(processIdentifier) (\(processName)) exited with code \(exitCode)"
    }
  }
}
