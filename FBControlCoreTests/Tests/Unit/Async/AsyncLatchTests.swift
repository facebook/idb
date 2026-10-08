/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct AsyncLatchTests {

  @Test
  func aLatchStartsClosed() {
    #expect(!AsyncLatch().isOpen)
  }

  @Test
  func aWaitAfterOpeningReturns() async throws {
    let latch = AsyncLatch()
    latch.open()

    try await latch.wait()
    #expect(latch.isOpen)
  }

  @Test
  func openingReleasesEveryWaiter() async throws {
    let latch = AsyncLatch()
    let waiters = (0..<3).map { _ in Task { try await latch.wait() } }
    try await Task.sleep(nanoseconds: 50_000_000)

    latch.open()

    for waiter in waiters {
      try await waiter.value
    }
  }

  @Test
  func openingTwiceIsHarmless() async throws {
    let latch = AsyncLatch()
    latch.open()
    latch.open()

    try await latch.wait()
  }

  @Test
  func cancellingOneWaiterLeavesTheOthersWaiting() async throws {
    let latch = AsyncLatch()
    let cancelled = Task { try await latch.wait() }
    let waiting = Task { try await latch.wait() }
    try await Task.sleep(nanoseconds: 50_000_000)

    cancelled.cancel()
    await #expect(throws: CancellationError.self) {
      try await cancelled.value
    }
    #expect(!latch.isOpen)

    latch.open()
    try await waiting.value
  }

  @Test
  func aWaitFromACancelledTaskThrows() async {
    let latch = AsyncLatch()
    let waiter = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await latch.wait()
    }

    await #expect(throws: CancellationError.self) {
      try await waiter.value
    }
  }

  @Test
  func aLatchThatDoesNotOpenInTimeFailsNamingWhatWasAwaited() async {
    let latch = AsyncLatch()

    do {
      try await latch.wait(within: PollDeadline(timeout: 0.05, waitingFor: "the thing"))
      Issue.record("The wait should time out")
    } catch {
      #expect(error is PollTimeoutError)
      #expect(error.localizedDescription.contains("seconds waiting for the thing"))
    }
  }

  @Test
  func aLatchThatOpensInTimeIsNotATimeout() async throws {
    let latch = AsyncLatch()
    latch.open()

    try await latch.wait(within: PollDeadline(timeout: 10, waitingFor: "the thing"))
  }
}
