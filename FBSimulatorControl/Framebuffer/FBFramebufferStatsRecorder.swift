/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import IOSurface

/// Accumulates framebuffer surface-change and damage counters and periodically logs interval/total
/// rates. Owns the single lock guarding the counters and the cadence timer: the callbacks that feed
/// it fire on arbitrary private-framework threads while `snapshot()` / `startTime` are read from a
/// consumer's queue.
final class FBFramebufferStatsRecorder: @unchecked Sendable {

  private let logger: any FBControlCoreLogger
  private let lock = NSLock()
  private var stats = FBFramebufferStats()
  private var lastLoggedStats = FBFramebufferStats()
  private var timer = FBPeriodicStatsTimer(interval: 5.0)

  init(logger: any FBControlCoreLogger) {
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

  func recordDamage(_ damage: FBFramebufferDamage) {
    lock.lock()
    stats.damageCallbackCount += 1
    stats.damageRectCount += UInt(damage.rects.count)
    if damage.rects.isEmpty {
      stats.emptyDamageCallbackCount += 1
    }
    lock.unlock()
    logStatsIfNeeded()
  }

  func snapshot() -> FBFramebufferStats {
    lock.lock()
    defer { lock.unlock() }
    return stats
  }

  var startTime: CFTimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return timer.firstTickTime
  }

  private func logStatsIfNeeded() {
    lock.lock()
    switch timer.tick() {
    case .started:
      lock.unlock()
      logger.info().log("First damage callback received")
    case .pending:
      lock.unlock()
    case let .elapsed(intervalDuration, totalElapsed):
      let current = stats
      let last = lastLoggedStats
      lastLoggedStats = current
      lock.unlock()

      let intervalCallbacks = current.damageCallbackCount - last.damageCallbackCount
      let intervalRects = current.damageRectCount - last.damageRectCount
      let intervalEmpty = current.emptyDamageCallbackCount - last.emptyDamageCallbackCount
      let intervalIOSurface = current.ioSurfaceChangeCount - last.ioSurfaceChangeCount

      let intervalRate = intervalDuration > 0 ? Double(intervalCallbacks) / intervalDuration : 0
      let totalRate = totalElapsed > 0 ? Double(current.damageCallbackCount) / totalElapsed : 0

      logger.info().log(
        String(
          format: "Framebuffer stats (interval): %lu damage callbacks in %.1fs (%.1f/s, %lu rects, %lu empty) — %lu IOSurface changes",
          intervalCallbacks, intervalDuration, intervalRate, intervalRects, intervalEmpty, intervalIOSurface))
      logger.info().log(
        String(
          format: "Framebuffer stats (total): %lu damage callbacks in %.1fs (%.1f/s, %lu rects, %lu empty) — %lu IOSurface changes",
          current.damageCallbackCount, totalElapsed, totalRate, current.damageRectCount, current.emptyDamageCallbackCount, current.ioSurfaceChangeCount))
    }
  }
}
