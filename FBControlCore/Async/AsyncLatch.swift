/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Something that happens once and that any number of callers can wait for, before or after it
/// happens. Only its owner can open it, so a waiter cannot release the others early.
// SAFETY: `state` is only touched under `lock`.
public final class AsyncLatch: @unchecked Sendable {
  private enum State {
    case closed(waiters: [UUID: CheckedContinuation<Void, Error>])
    case open
  }

  private let lock = NSLock()
  private var state = State.closed(waiters: [:])

  init() {}

  public var isOpen: Bool {
    lock.withLock {
      switch state {
      case .open:
        return true
      case .closed:
        return false
      }
    }
  }

  /// Releases every waiter, and every later one. Opening an open latch does nothing.
  func open() {
    let waiters: [UUID: CheckedContinuation<Void, Error>] = lock.withLock {
      guard case let .closed(waiters) = state else {
        return [:]
      }
      state = .open
      return waiters
    }
    for waiter in waiters.values {
      waiter.resume()
    }
  }

  /// Returns once the latch is open. Cancelling throws `CancellationError` without affecting other
  /// waiters.
  public func wait() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        lock.lock()
        switch state {
        case .open:
          lock.unlock()
          continuation.resume()
        case .closed where Task.isCancelled:
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        case var .closed(waiters):
          waiters[id] = continuation
          state = .closed(waiters: waiters)
          lock.unlock()
        }
      }
    } onCancel: {
      let waiter: CheckedContinuation<Void, Error>? = lock.withLock {
        guard case var .closed(waiters) = state, let waiter = waiters.removeValue(forKey: id) else {
          return nil
        }
        state = .closed(waiters: waiters)
        return waiter
      }
      waiter?.resume(throwing: CancellationError())
    }
  }

  /// As `wait()`, throwing `PollTimeoutError` if the latch has not opened by `deadline`.
  public func wait(within deadline: PollDeadline) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await self.wait()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(max(deadline.timeout, 0) * Double(NSEC_PER_SEC)))
        throw PollTimeoutError(deadline: deadline)
      }
      defer { group.cancelAll() }
      try await group.next()
    }
  }
}
