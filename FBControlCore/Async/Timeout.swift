/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Runs `operation`, throwing `timeoutError()` if it has not finished within `timeout` seconds, in which
/// case the operation is cancelled and waited for before the error is thrown. A negative timeout times
/// out at once.
public func withTimeout<T: Sendable>(
  _ timeout: TimeInterval,
  orThrow timeoutError: @escaping @Sendable () -> any Error,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      try await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
      throw timeoutError()
    }
    defer { group.cancelAll() }
    guard let first = try await group.next() else {
      preconditionFailure("The task group has two children; next() cannot be empty")
    }
    return first
  }
}
