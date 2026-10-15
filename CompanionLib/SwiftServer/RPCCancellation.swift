/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import GRPCCore

/// Runs `operation` until it finishes or `cancellation` reports the RPC cancelled, as it does when the
/// client goes away, and cancels `operation`'s task in that case.
///
/// gRPC signals a client going away through `cancellation` rather than by cancelling the handler's task.
/// Both children are joined, so `operation` has finished its cleanup by the time this returns.
func withRPCCancellation<T: Sendable>(
  _ cancellation: ServerContext.RPCCancellationHandle, operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      guard !cancellation.isCancelled else { throw CancellationError() }
      return try await operation()
    }
    group.addTask {
      try await cancellation.cancelled
      throw CancellationError()
    }
    defer { group.cancelAll() }
    guard let result = try await group.next() else { throw CancellationError() }
    return result
  }
}
