/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// How long a polling loop may run for, and what it is waiting on.
///
/// The two are paired in one value so that a timeout cannot be requested without
/// a description to report when it fires.
public struct PollDeadline: Sendable {

  /// How long polling may continue before the deadline is exceeded.
  public let timeout: TimeInterval

  /// What the caller is waiting for, as it should read in a timeout message.
  public let waitingFor: String

  public init(timeout: TimeInterval, waitingFor: String) {
    self.timeout = timeout
    self.waitingFor = waitingFor
  }
}

/// The error thrown when a polling loop exceeds its ``PollDeadline``.
public struct PollTimeoutError: Error, LocalizedError {

  public let deadline: PollDeadline

  public var errorDescription: String? {
    "Timed out after \(deadline.timeout) seconds waiting for \(deadline.waitingFor)"
  }
}

/// Polls a condition on a queue until it returns true.
///
/// This is the Swift async equivalent of `FBFuture.onQueue(_:resolveWhen:)`. Each
/// poll evaluates the condition on the supplied dispatch queue, then suspends
/// for `interval` before the next attempt. Throws ``CancellationError`` if the
/// surrounding task is cancelled while waiting.
///
/// A `deadline` is enforced at poll granularity: it is tested after each
/// unsatisfied poll, so a condition that becomes true on the same poll that the
/// deadline expires still succeeds, and a timeout is reported up to `interval`
/// after the deadline itself.
///
/// - Parameters:
///   - queue: The queue to evaluate the condition on. The condition is hopped
///     onto this queue for each poll, matching the threading guarantees of the
///     original FBFuture API.
///   - interval: The delay between polls. Defaults to 100 milliseconds, the
///     same cadence as `resolveWhen:`.
///   - deadline: How long to keep polling for. Polls indefinitely when `nil`.
///   - condition: A closure that returns `true` once polling should stop.
/// - Throws: ``PollTimeoutError`` if `deadline` elapses before the condition is
///   satisfied.
public func pollUntilTrue(
  on queue: DispatchQueue,
  interval: TimeInterval = 0.1,
  deadline: PollDeadline? = nil,
  condition: @escaping @Sendable () -> Bool
) async throws {
  let expiry = deadline.map { (deadline: $0, time: DispatchTime.now() + $0.timeout) }
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
    if let expiry, DispatchTime.now() >= expiry.time {
      throw PollTimeoutError(deadline: expiry.deadline)
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
