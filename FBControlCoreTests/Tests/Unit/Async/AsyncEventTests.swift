/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

private struct EventTestError: Error {}

@Suite
struct AsyncEventTests {

  @Test
  func anEventThatHappenedBeforeTheWaitIsDelivered() async throws {
    let event = AsyncEvent<Int>()
    event.happen(42)

    #expect(try await event.wait() == 42)
    #expect(event.hasHappened)
  }

  @Test
  func anEventThatHappensDuringTheWaitIsDelivered() async throws {
    let event = AsyncEvent<Int>()
    let waiter = Task { try await event.wait() }
    try await Task.sleep(nanoseconds: 50_000_000)

    event.happen(42)

    #expect(try await waiter.value == 42)
  }

  @Test
  func onlyTheFirstOutcomeCounts() async throws {
    let event = AsyncEvent<Int>()
    event.happen(1)
    event.fail(EventTestError())
    event.happen(2)

    #expect(try await event.wait() == 1)
  }

  @Test
  func aFailedEventThrowsAndHasHappened() async {
    let event = AsyncEvent<Void>()
    event.fail(EventTestError())

    #expect(event.hasHappened)
    await #expect(throws: EventTestError.self) {
      try await event.wait()
    }
  }

  @Test
  func cancellingTheWaitLeavesTheEventToBeWaitedOnAgain() async throws {
    let event = AsyncEvent<Int>()
    let waiter = Task { try await event.wait() }
    try await Task.sleep(nanoseconds: 50_000_000)
    waiter.cancel()
    await #expect(throws: CancellationError.self) {
      try await waiter.value
    }

    event.happen(42)

    #expect(try await event.wait() == 42)
  }

  @Test
  func anEventThatDoesNotHappenInTimeFailsNamingWhatWasAwaited() async {
    let event = AsyncEvent<Void>()

    do {
      try await event.wait(timeout: 0.05, waitingFor: "the thing")
      Issue.record("The wait should time out")
    } catch {
      #expect(error.localizedDescription.contains("seconds waiting for the thing"))
    }
  }
}
