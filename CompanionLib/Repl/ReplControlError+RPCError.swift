/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorCodeInjection
import GRPCCore

extension ReplControlError {
  /// The status the `repl` method ends with when the control socket fails.
  var rpcError: RPCError {
    let code: RPCError.Code
    switch self {
    case .socketPathTooLong:
      code = .invalidArgument
    case .connectTimedOut:
      code = .deadlineExceeded
    case .disconnected:
      code = .unavailable
    case .socketCreationFailed, .missingGreeting, .unexpectedMessage, .invalidMessage, .readFailed, .writeFailed, .hostCommandDidNotComplete:
      code = .internalError
    }
    return RPCError(code: code, message: description)
  }
}

/// Runs `body`, reporting a control-socket failure as the status the `repl` method ends with.
func reportingReplControlErrors<T>(_ body: () async throws -> T) async throws -> T {
  do {
    return try await body()
  } catch let error as ReplControlError {
    throw error.rpcError
  }
}
