/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Polls a condition on a queue until it returns true.
///
/// This is the Swift async equivalent of `FBFuture.onQueue(_:resolveWhen:)`. Each
/// poll evaluates the condition on the supplied dispatch queue, then suspends
/// for `interval` before the next attempt. Throws ``CancellationError`` if the
/// surrounding task is cancelled while waiting.
///
/// - Parameters:
///   - queue: The queue to evaluate the condition on. The condition is hopped
///     onto this queue for each poll, matching the threading guarantees of the
///     original FBFuture API.
///   - interval: The delay between polls. Defaults to 100 milliseconds, the
///     same cadence as `resolveWhen:`.
///   - condition: A closure that returns `true` once polling should stop.
public func pollUntilTrue(
  on queue: DispatchQueue,
  interval: TimeInterval = 0.1,
  condition: @escaping @Sendable () -> Bool
) async throws {
  while true {
    try Task.checkCancellation()
    let satisfied = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      queue.async {
        continuation.resume(returning: condition())
      }
    }
    if satisfied {
      return
    }
    try await Task.sleep(nanoseconds: nanoseconds(from: interval))
  }
}

/// Retries an async operation until it succeeds.
///
/// This is the Swift async equivalent of `FBFuture.onQueue(_:resolveUntil:)`.
/// Whenever `operation` throws, the function suspends for `interval` and tries
/// again. Cancellation of the surrounding task short-circuits the loop and
/// rethrows ``CancellationError``.
///
/// - Parameters:
///   - interval: The delay between attempts. Defaults to 100 milliseconds.
///   - operation: The work to attempt. Returns the value on the first success.
/// - Returns: The result of the first successful invocation of `operation`.
public func retryUntilSuccess<T>(
  interval: TimeInterval = 0.1,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  while true {
    try Task.checkCancellation()
    do {
      return try await operation()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try await Task.sleep(nanoseconds: nanoseconds(from: interval))
    }
  }
}

private func nanoseconds(from interval: TimeInterval) -> UInt64 {
  let clamped = max(interval, 0)
  return UInt64(clamped * Double(NSEC_PER_SEC))
}
