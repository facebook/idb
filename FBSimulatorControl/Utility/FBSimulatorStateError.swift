/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// State-guard failure for operations that require the simulator to be in a particular state.
public enum FBSimulatorStateError: Error, LocalizedError {
  case notBooted(operation: String, state: String)
  case notShutdown(operation: String, state: String)
  case unknownState(operation: String)

  public var errorDescription: String? {
    switch self {
    case let .notBooted(operation, state):
      return "Simulator must be booted to \(operation), but it is in the \(state) state"
    case let .notShutdown(operation, state):
      return "Simulator must be shut down to \(operation), but it is in the \(state) state"
    case let .unknownState(operation):
      return "Simulator is in an unknown state, cannot \(operation)"
    }
  }
}
