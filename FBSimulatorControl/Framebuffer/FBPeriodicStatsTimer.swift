/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreFoundation

/// Shared timing logic for periodic stats logging across the framebuffer and the encoder. Not part of
/// the public API.
struct FBPeriodicStatsTimer {
  private var startTime: CFAbsoluteTime = 0
  private var lastLogTime: CFAbsoluteTime = 0
  private let interval: CFTimeInterval

  /// Initialize with a log interval (e.g. 5.0 seconds).
  init(interval: CFTimeInterval) {
    self.interval = interval
  }

  /// Whether the first tick has been seen.
  var hasStarted: Bool { startTime != 0 }

  /// Absolute time of the first tick, or 0 before it.
  var firstTickTime: CFAbsoluteTime { startTime }

  enum Tick: Equatable {
    /// The very first tick — the timer is now started.
    case started
    /// Not enough time has elapsed since the last log.
    case pending
    /// The interval elapsed; carries the elapsed durations since the last log and since the start.
    case elapsed(intervalDuration: CFTimeInterval, totalElapsed: CFTimeInterval)
  }

  /// Record a tick. On the very first call it starts the timer and returns `.started`; afterwards it
  /// returns `.elapsed` once at least `interval` has passed since the last log, else `.pending`.
  mutating func tick() -> Tick {
    let now = CFAbsoluteTimeGetCurrent()
    if startTime == 0 {
      startTime = now
      lastLogTime = now
      return .started
    }
    if now - lastLogTime < interval {
      return .pending
    }
    let intervalDuration = now - lastLogTime
    let totalElapsed = now - startTime
    lastLogTime = now
    return .elapsed(intervalDuration: intervalDuration, totalElapsed: totalElapsed)
  }

  /// Test seam: move the last-log time back by `seconds` so the next `tick()` reports `.elapsed`.
  mutating func backdateForTesting(by seconds: CFTimeInterval) {
    lastLogTime -= seconds
  }
}
