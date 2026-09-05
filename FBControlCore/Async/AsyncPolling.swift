/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A timeout paired with the description reported when it fires.
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

/// Async equivalent of `FBFuture.onQueue(_:resolveWhen:)`: evaluates `condition` on `queue` every `interval`
/// until it returns true. `deadline` is checked only after an unsatisfied poll, so a timeout surfaces up to
/// `interval` late; `nil` polls forever. Throws `PollTimeoutError` on deadline, `CancellationError` if cancelled.
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

/// Async equivalent of `FBFuture.onQueue(_:resolveUntil:)`: retries `operation` every `interval` until it
/// returns; only `CancellationError` is rethrown.
func retryUntilSuccess<T>(
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
