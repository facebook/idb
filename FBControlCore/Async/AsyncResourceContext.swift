/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Acquires a resource, runs `body`, then guarantees `cleanup` is invoked.
///
/// This is the Swift async equivalent of an `FBFutureContext` (the
/// `pend`/`push`/`pop`/`contextualTeardown` API). The resource lifetime is
/// scoped to the duration of `body`. If `body` throws, the cleanup still runs
/// and the original error is rethrown; an error from cleanup in that path is
/// suppressed so as not to mask the cause.
///
/// To stack multiple resources with LIFO teardown, nest calls:
///
/// ```swift
/// try await withAsyncResource(
///   acquire: openSocket,
///   cleanup: closeSocket
/// ) { socket in
///   try await withAsyncResource(
///     acquire: { try await startReader(on: socket) },
///     cleanup: stopReader
///   ) { reader in
///     try await reader.run()
///   }
/// }
/// ```
///
/// - Parameters:
///   - acquire: Creates or acquires the resource. Errors propagate without
///     calling cleanup, since no resource was held.
///   - cleanup: Releases the resource. Always runs after a successful `body`,
///     and best-effort after a failing `body`.
///   - body: Uses the resource. The result is returned to the caller.
/// - Returns: The result of `body`.
public func withAsyncResource<T, R>(
  acquire: () async throws -> T,
  cleanup: (T) async throws -> Void,
  body: (T) async throws -> R
) async throws -> R {
  let resource = try await acquire()
  do {
    let result = try await body(resource)
    try await cleanup(resource)
    return result
  } catch {
    try? await cleanup(resource)
    throw error
  }
}
