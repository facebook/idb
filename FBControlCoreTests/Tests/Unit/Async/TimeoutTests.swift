/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

private struct TimedOut: Error {}

@Suite
struct TimeoutTests {

  @Test
  func returnsWhatAnOperationThatFinishesInTimeReturns() async throws {
    #expect(try await withTimeout(10, orThrow: { TimedOut() }) { 42 } == 42)
  }

  @Test
  func throwsTheTimeoutErrorAndCancelsAnOperationThatOverruns() async {
    let cancelled = AsyncEvent<Void>()

    await #expect(throws: TimedOut.self) {
      try await withTimeout(0.05, orThrow: { TimedOut() }) {
        do {
          try await Task.sleep(nanoseconds: 10_000_000_000)
        } catch {
          cancelled.happen()
          throw error
        }
      }
    }
    #expect(cancelled.hasHappened)
  }
}
