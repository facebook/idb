/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import os

/// Counters that are bumped from arbitrary threads and summarised every few seconds: the current
/// state, the state as of the last summary, and the `PeriodicStatsTimer` that decides when the next
/// one is due, all under one lock. Callers mutate through `update` and format their own summary from
/// what `tick` hands back, so the log lines stay with the type that knows what the counters mean.
final class PeriodicStatsLog<State: Sendable>: Sendable {

  enum Tick: Sendable {
    /// The very first tick — the timer is now started.
    case started
    /// Not enough time has elapsed since the last summary.
    case pending
    /// A summary is due: the state now, the state at the last summary, and the two elapsed spans.
    case elapsed(current: State, last: State, interval: Duration, total: Duration)
  }

  private struct Guarded {
    var state: State
    var lastLogged: State
    var timer: PeriodicStatsTimer
  }

  private let guarded: OSAllocatedUnfairLock<Guarded>

  init(initial: State, interval: Duration = .seconds(5)) {
    self.guarded = OSAllocatedUnfairLock(initialState: Guarded(state: initial, lastLogged: initial, timer: PeriodicStatsTimer(interval: interval)))
  }

  /// The state now.
  var snapshot: State {
    guarded.withLock { $0.state }
  }

  /// When the first tick happened, or nil before it.
  var startTime: ContinuousClock.Instant? {
    guarded.withLock { $0.timer.firstTickTime }
  }

  /// Mutates the state under the lock and returns whatever `body` does.
  func update<R: Sendable>(_ body: @Sendable (inout State) -> R) -> R {
    guarded.withLock { body(&$0.state) }
  }

  /// Mutates the state and advances the timer in one critical section, so a summary that is due is
  /// computed against the state that includes this update. On `.elapsed`, the last-summary state
  /// moves forward to now. Returns whatever `body` does beside the tick.
  func updateAndTick<R: Sendable>(_ body: @Sendable (inout State) -> R) -> (R, Tick) {
    guarded.withLock { guarded in
      let result = body(&guarded.state)
      return (result, Self.advance(&guarded))
    }
  }

  /// Test seam: move the last-summary time back so the next tick reports `.elapsed`.
  func backdateForTesting(by duration: Duration) {
    guarded.withLock { $0.timer.backdateForTesting(by: duration) }
  }

  private static func advance(_ guarded: inout Guarded) -> Tick {
    switch guarded.timer.tick() {
    case .started:
      return .started
    case .pending:
      return .pending
    case let .elapsed(intervalDuration, totalElapsed):
      let current = guarded.state
      let last = guarded.lastLogged
      guarded.lastLogged = current
      return .elapsed(current: current, last: last, interval: intervalDuration, total: totalElapsed)
    }
  }
}
