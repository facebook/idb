/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Asks a running profiler to finish early and report what it has recorded so far.
///
// SAFETY: `requested`, `waiters` and `cancelledWaiters` are only ever read or written inside `lock`, and every
// continuation is resumed after the lock is released, so no caller code runs under it.
// patternlint-disable-next-line unchecked-sendable
public final class ProfileStopRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var requested = false
  private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
  private var cancelledWaiters: Set<UUID> = []

  init() {}

  func request() {
    let continuations: [CheckedContinuation<Void, any Error>] = lock.withLock {
      guard !requested else {
        return []
      }
      requested = true
      let pending = Array(waiters.values)
      waiters.removeAll()
      return pending
    }
    for continuation in continuations {
      continuation.resume()
    }
  }

  /// Returns once a stop has been requested. Throws only `CancellationError`.
  public func wait() async throws {
    let identifier = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let immediate: Result<Void, any Error>? = lock.withLock {
          if cancelledWaiters.remove(identifier) != nil {
            return .failure(CancellationError())
          }
          if requested {
            return .success(())
          }
          waiters[identifier] = continuation
          return nil
        }
        if let immediate {
          continuation.resume(with: immediate)
        }
      }
    } onCancel: {
      let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
        guard let waiting = waiters.removeValue(forKey: identifier) else {
          cancelledWaiters.insert(identifier)
          return nil
        }
        return waiting
      }
      continuation?.resume(throwing: CancellationError())
    }
  }
}
