/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Shared timing logic for periodic stats logging across the framebuffer and the encoder. Runs on
/// the monotonic `ContinuousClock`, so a wall-clock step never fires or starves a log.
struct PeriodicStatsTimer {
  private var startTime: ContinuousClock.Instant?
  private var lastLogTime: ContinuousClock.Instant?
  private let interval: Duration

  /// Initialize with a log interval (e.g. five seconds).
  init(interval: Duration) {
    self.interval = interval
  }

  /// Whether the first tick has been seen.
  var hasStarted: Bool { startTime != nil }

  /// When the first tick happened, or nil before it.
  var firstTickTime: ContinuousClock.Instant? { startTime }

  enum Tick: Equatable {
    /// The very first tick — the timer is now started.
    case started
    /// Not enough time has elapsed since the last log.
    case pending
    /// The interval elapsed; carries the elapsed durations since the last log and since the start.
    case elapsed(intervalDuration: Duration, totalElapsed: Duration)
  }

  /// Record a tick. On the very first call it starts the timer and returns `.started`; afterwards it
  /// returns `.elapsed` once at least `interval` has passed since the last log, else `.pending`.
  mutating func tick() -> Tick {
    let now = ContinuousClock.now
    guard let startTime, let lastLogTime else {
      self.startTime = now
      self.lastLogTime = now
      return .started
    }
    if now - lastLogTime < interval {
      return .pending
    }
    self.lastLogTime = now
    return .elapsed(intervalDuration: now - lastLogTime, totalElapsed: now - startTime)
  }

  /// Test seam: move the last-log time back so the next `tick()` reports `.elapsed`.
  mutating func backdateForTesting(by duration: Duration) {
    lastLogTime = lastLogTime.map { $0 - duration }
  }
}

extension Duration {
  /// The duration in seconds, for rates and averages.
  var seconds: TimeInterval {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
