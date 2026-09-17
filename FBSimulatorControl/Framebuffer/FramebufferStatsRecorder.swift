/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import IOSurface

/// Accumulates framebuffer surface-change and frame-rendered counters and periodically logs
/// interval/total rates. Owns the single lock guarding the counters and the cadence timer: the
/// callbacks that feed it fire on arbitrary private-framework threads while `snapshot()` /
/// `startTime` are read from a consumer's queue.
final class FramebufferStatsRecorder: @unchecked Sendable {

  private let logger: any ControlCoreLogger
  private let lock = NSLock()
  private var stats = FramebufferStats()
  private var lastLoggedStats = FramebufferStats()
  private var timer = PeriodicStatsTimer(interval: .seconds(5))

  init(logger: any ControlCoreLogger) {
    self.logger = logger
  }

  func recordIOSurfaceChange(surface: IOSurface?) {
    lock.lock()
    stats.ioSurfaceChangeCount += 1
    let isFirstChange = stats.ioSurfaceChangeCount == 1
    lock.unlock()
    if isFirstChange {
      logger.info().log("First IOSurface change callback, surface=\(String(describing: surface))")
    }
  }

  func recordFrameRendered() {
    lock.lock()
    stats.frameRenderedCount += 1
    lock.unlock()
    logStatsIfNeeded()
  }

  func snapshot() -> FramebufferStats {
    lock.lock()
    defer { lock.unlock() }
    return stats
  }

  var startTime: ContinuousClock.Instant? {
    lock.lock()
    defer { lock.unlock() }
    return timer.firstTickTime
  }

  private func logStatsIfNeeded() {
    lock.lock()
    switch timer.tick() {
    case .started:
      lock.unlock()
      logger.info().log("First frame-rendered callback received")
    case .pending:
      lock.unlock()
    case let .elapsed(intervalDuration, totalElapsed):
      let current = stats
      let last = lastLoggedStats
      lastLoggedStats = current
      lock.unlock()

      let intervalCallbacks = current.frameRenderedCount - last.frameRenderedCount
      let intervalIOSurface = current.ioSurfaceChangeCount - last.ioSurfaceChangeCount

      let intervalSeconds = intervalDuration.seconds
      let totalSeconds = totalElapsed.seconds
      let intervalRate = intervalSeconds > 0 ? Double(intervalCallbacks) / intervalSeconds : 0
      let totalRate = totalSeconds > 0 ? Double(current.frameRenderedCount) / totalSeconds : 0

      logger.info().log(
        String(
          format: "Framebuffer stats (interval): %lu frames in %.1fs (%.1f/s) — %lu IOSurface changes",
          intervalCallbacks, intervalSeconds, intervalRate, intervalIOSurface))
      logger.info().log(
        String(
          format: "Framebuffer stats (total): %lu frames in %.1fs (%.1f/s) — %lu IOSurface changes",
          current.frameRenderedCount, totalSeconds, totalRate, current.ioSurfaceChangeCount))
    }
  }
}
