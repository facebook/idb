/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

private struct PollingTestError: Error {}

/// A counter the polled closures can mutate. The closures run on a dispatch queue rather than in an
/// actor context, so the count has to be reachable synchronously.
private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  var count: Int {
    lock.withLock { value }
  }

  @discardableResult
  func increment() -> Int {
    lock.withLock {
      value += 1
      return value
    }
  }
}

@Suite("Async polling")
struct AsyncPollingTests {

  /// Long enough that a test taking the sleep path would hang rather than flake.
  private static let neverElapsingInterval: TimeInterval = 1000

  private static let fastInterval: TimeInterval = 0.01

  @Test("An already-satisfied condition returns without waiting for the interval")
  func satisfiedConditionDoesNotWait() async throws {
    try await pollUntilTrue(on: .global(), interval: Self.neverElapsingInterval) { true }
  }

  @Test("The condition is polled until it becomes true")
  func pollsUntilSatisfied() async throws {
    let counter = Counter()
    try await pollUntilTrue(on: .global(), interval: Self.fastInterval) {
      counter.increment() == 3
    }
    #expect(counter.count == 3)
  }

  @Test("The condition is evaluated on the supplied queue")
  func evaluatesConditionOnSuppliedQueue() async throws {
    let key = DispatchSpecificKey<String>()
    let queue = DispatchQueue(label: "AsyncPollingTests.condition")
    queue.setSpecific(key: key, value: "expected")

    let observed = Counter()
    try await pollUntilTrue(on: queue, interval: Self.fastInterval) {
      if DispatchQueue.getSpecific(key: key) == "expected" {
        observed.increment()
      }
      return true
    }
    #expect(observed.count == 1)
  }

  @Test("Cancellation while polling throws CancellationError")
  func pollingIsCancellable() async throws {
    let task = Task {
      try await pollUntilTrue(on: .global(), interval: Self.fastInterval) { false }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test("An operation that succeeds first time is not retried")
  func successfulOperationIsNotRetried() async throws {
    let counter = Counter()
    let result = try await retryUntilSuccess(interval: Self.neverElapsingInterval) { () -> String in
      counter.increment()
      return "ok"
    }
    #expect(result == "ok")
    #expect(counter.count == 1)
  }

  @Test("A failing operation is retried until it succeeds")
  func failingOperationIsRetried() async throws {
    let counter = Counter()
    let result = try await retryUntilSuccess(interval: Self.fastInterval) { () -> String in
      if counter.increment() < 3 {
        throw PollingTestError()
      }
      return "ok"
    }
    #expect(result == "ok")
    #expect(counter.count == 3)
  }

  @Test("Cancellation while retrying throws CancellationError")
  func retryingIsCancellable() async throws {
    let task = Task {
      try await retryUntilSuccess(interval: Self.fastInterval) { () -> String in
        throw PollingTestError()
      }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }
}
