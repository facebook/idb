/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Something to wait for that may happen, or fail, before it is waited on. Only the first outcome
/// counts.
public final class AsyncEvent<Value: Sendable>: @unchecked Sendable {
  private enum State {
    case pending
    case waiting(CheckedContinuation<Value, Error>)
    case happened(Result<Value, Error>)
  }

  private let lock = NSLock()
  private var state = State.pending

  public init() {}

  /// Whether the event has happened, successfully or not.
  public var hasHappened: Bool {
    lock.withLock {
      switch state {
      case .happened:
        return true
      case .pending, .waiting:
        return false
      }
    }
  }

  public func happen(_ value: Value) {
    resolve(.success(value))
  }

  public func fail(_ error: Error) {
    resolve(.failure(error))
  }

  /// Returns once the event has happened, throwing if it failed. Cancelling throws
  /// `CancellationError` and leaves the event to be waited on again.
  public func wait() async throws -> Value {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
        lock.lock()
        switch state {
        case let .happened(result):
          lock.unlock()
          continuation.resume(with: result)
        case .pending where Task.isCancelled:
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        case .pending:
          state = .waiting(continuation)
          lock.unlock()
        case .waiting:
          lock.unlock()
          preconditionFailure("An AsyncEvent has one waiter at a time")
        }
      }
    } onCancel: {
      lock.lock()
      guard case let .waiting(continuation) = state else {
        lock.unlock()
        return
      }
      state = .pending
      lock.unlock()
      continuation.resume(throwing: CancellationError())
    }
  }

  /// As `wait()`, failing with a `ControlCoreError` naming `description` if the event has not
  /// happened within `timeout` seconds.
  public func wait(timeout: TimeInterval, waitingFor description: String) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask {
        try await self.wait()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw ControlCoreError.describe("Timed out after \(String(format: "%f", timeout)) seconds waiting for \(description)").build()
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else {
        preconditionFailure("The task group has two children; next() cannot be empty")
      }
      return first
    }
  }

  private func resolve(_ result: Result<Value, Error>) {
    lock.lock()
    switch state {
    case .pending:
      state = .happened(result)
      lock.unlock()
    case let .waiting(continuation):
      state = .happened(result)
      lock.unlock()
      continuation.resume(with: result)
    case .happened:
      lock.unlock()
    }
  }
}

extension AsyncEvent where Value == Void {
  public func happen() {
    happen(())
  }
}
