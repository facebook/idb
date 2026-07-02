/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionUtilities
import XCTest

final class AsyncPromiseTests: XCTestCase {

  private enum TestError: Error, Equatable {
    case boom
  }

  func testResolveBeforeAwaitReturnsValue() async throws {
    let promise = AsyncPromise<Int>()
    promise.resolve(42)
    let value = try await promise.value
    XCTAssertEqual(value, 42)
  }

  func testAwaitBeforeResolveReturnsValue() async throws {
    let promise = AsyncPromise<Int>()
    let waiter = Task { try await promise.value }
    promise.resolve(7)
    let value = try await waiter.value
    XCTAssertEqual(value, 7)
  }

  func testFailPropagatesError() async {
    let promise = AsyncPromise<Int>()
    promise.fail(TestError.boom)
    do {
      _ = try await promise.value
      XCTFail("Expected the promise to throw")
    } catch let error as TestError {
      XCTAssertEqual(error, .boom)
    } catch {
      XCTFail("Expected TestError.boom, got \(error)")
    }
  }

  func testFirstResolutionWins() async throws {
    let promise = AsyncPromise<Int>()
    promise.resolve(1)
    promise.resolve(2)
    promise.fail(TestError.boom)
    let value = try await promise.value
    XCTAssertEqual(value, 1, "Only the first resolution should take effect")
  }

  func testIsResolved() {
    let promise = AsyncPromise<Int>()
    XCTAssertFalse(promise.isResolved)
    promise.resolve(1)
    XCTAssertTrue(promise.isResolved)
  }

  func testVoidPromiseResolves() async throws {
    let promise = AsyncPromise<Void>()
    let waiter = Task { try await promise.value }
    promise.resolve(())
    try await waiter.value
  }

  func testCancellationThrowsCancellationError() async {
    let promise = AsyncPromise<Int>()
    let waiter = Task { try await promise.value }
    waiter.cancel()
    do {
      _ = try await waiter.value
      XCTFail("Expected cancellation to throw")
    } catch is CancellationError {
      // expected
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testCancellingOneWaiterDoesNotAffectOthers() async throws {
    let promise = AsyncPromise<Int>()
    let cancelled = Task { try await promise.value }
    let survivor = Task { try await promise.value }

    cancelled.cancel()
    do {
      _ = try await cancelled.value
      XCTFail("Expected the cancelled waiter to throw")
    } catch is CancellationError {
      // expected
    }

    // A later resolution still reaches a waiter that was never cancelled.
    promise.resolve(99)
    let value = try await survivor.value
    XCTAssertEqual(value, 99)
  }

  func testMultipleWaitersAllReceiveValue() async throws {
    let promise = AsyncPromise<Int>()
    let first = Task { try await promise.value }
    let second = Task { try await promise.value }
    promise.resolve(5)
    let firstValue = try await first.value
    let secondValue = try await second.value
    XCTAssertEqual(firstValue, 5)
    XCTAssertEqual(secondValue, 5)
  }
}
