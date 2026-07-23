/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A one-shot, thread-safe awaitable value that can be resolved (or failed) from
/// synchronous, non-`async` code — e.g. a dispatch timer handler, a SwiftNIO
/// completion callback, or an Objective-C delegate method — and awaited from an
/// `async` context.
///
/// The first ``resolve(_:)`` or ``fail(_:)`` wins; later calls are ignored
/// (matching the one-shot semantics of `FBMutableFuture`, which this replaces).
/// Awaiting ``value`` participates in cooperative cancellation: if the awaiting
/// task is cancelled before the promise is resolved, the await throws
/// `CancellationError`. A value that is already resolved is delivered even to a
/// cancelled task.
public final class AsyncPromise<Value: Sendable>: @unchecked Sendable {

  private enum State {
    case pending
    case resolved(Result<Value, Error>)
  }

  private let mutex = FBMutex()
  private var state: State = .pending
  private var waiters: [Int: CheckedContinuation<Value, Error>] = [:]
  /// IDs whose cancellation handler fired before their continuation registered,
  /// so registration knows to resume with `CancellationError` immediately.
  private var cancelledWaiterIDs: Set<Int> = []
  private var nextWaiterID = 0

  public init() {}

  /// Whether the promise has already been resolved or failed.
  public var isResolved: Bool {
    mutex.sync {
      if case .resolved = state { return true }
      return false
    }
  }

  /// Resolves the promise with `value`. No-op if already resolved or failed.
  public func resolve(_ value: Value) {
    complete(.success(value))
  }

  /// Fails the promise with `error`. No-op if already resolved or failed.
  public func fail(_ error: Error) {
    complete(.failure(error))
  }

  /// The resolved value. Suspends until the promise is resolved or failed, or
  /// until the awaiting task is cancelled (which throws `CancellationError`).
  public var value: Value {
    get async throws {
      let id = mutex.sync { () -> Int in
        let id = nextWaiterID
        nextWaiterID += 1
        return id
      }
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let immediate = mutex.sync { () -> Result<Value, Error>? in
            switch state {
            case let .resolved(result):
              return result
            case .pending:
              if cancelledWaiterIDs.remove(id) != nil {
                return .failure(CancellationError())
              }
              waiters[id] = continuation
              return nil
            }
          }
          if let immediate {
            continuation.resume(with: immediate)
          }
        }
      } onCancel: {
        let continuation = mutex.sync { () -> CheckedContinuation<Value, Error>? in
          if let continuation = waiters.removeValue(forKey: id) {
            return continuation
          }
          // The continuation has not registered yet; record the cancellation so
          // registration resumes it immediately.
          cancelledWaiterIDs.insert(id)
          return nil
        }
        continuation?.resume(throwing: CancellationError())
      }
    }
  }

  private func complete(_ result: Result<Value, Error>) {
    let waitersToResume = mutex.sync { () -> [CheckedContinuation<Value, Error>]? in
      guard case .pending = state else { return nil }
      state = .resolved(result)
      let waitersToResume = Array(waiters.values)
      waiters.removeAll()
      cancelledWaiterIDs.removeAll()
      return waitersToResume
    }
    guard let waitersToResume else { return }
    for continuation in waitersToResume {
      continuation.resume(with: result)
    }
  }
}
