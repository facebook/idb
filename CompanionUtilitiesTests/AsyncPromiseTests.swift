/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionUtilities
import Testing

@Suite
struct AsyncPromiseTests {

  private enum TestError: Error, Equatable {
    case boom
  }

  @Test
  func resolveBeforeAwaitReturnsValue() async throws {
    let promise = AsyncPromise<Int>()
    promise.resolve(42)
    let value = try await promise.value
    #expect(value == 42)
  }

  @Test
  func failPropagatesError() async {
    let promise = AsyncPromise<Int>()
    promise.fail(TestError.boom)
    await #expect(throws: TestError.boom) { try await promise.value }
  }

  @Test
  func firstResolutionWins() async throws {
    let promise = AsyncPromise<Int>()
    promise.resolve(1)
    promise.resolve(2)
    promise.fail(TestError.boom)
    let value = try await promise.value
    #expect(value == 1, "Only the first resolution should take effect")
  }

  @Test
  func isResolved() {
    let promise = AsyncPromise<Int>()
    #expect(!promise.isResolved)
    promise.resolve(1)
    #expect(promise.isResolved)
  }

  @Test
  func voidPromiseResolves() async throws {
    let promise = AsyncPromise<Void>()
    let waiter = Task { try await promise.value }
    promise.resolve(())
    try await waiter.value
  }

  @Test
  func cancellationThrowsCancellationError() async {
    let promise = AsyncPromise<Int>()
    let waiter = Task { try await promise.value }
    waiter.cancel()
    await #expect(throws: CancellationError.self) { try await waiter.value }
  }

  @Test
  func cancellingOneWaiterDoesNotAffectOthers() async throws {
    let promise = AsyncPromise<Int>()
    let cancelled = Task { try await promise.value }
    let survivor = Task { try await promise.value }

    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }

    // A later resolution still reaches a waiter that was never cancelled.
    promise.resolve(99)
    let value = try await survivor.value
    #expect(value == 99)
  }

  @Test
  func multipleWaitersAllReceiveValue() async throws {
    let promise = AsyncPromise<Int>()
    let first = Task { try await promise.value }
    let second = Task { try await promise.value }
    promise.resolve(5)
    let firstValue = try await first.value
    let secondValue = try await second.value
    #expect(firstValue == 5)
    #expect(secondValue == 5)
  }
}
