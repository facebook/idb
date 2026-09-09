/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - FrameTrigger / FrameCadence / LazyFrameTriggers

/// A stimulus to push one frame, produced by either cadence: the `FrameCadence` clock (eager) or
/// `LazyFrameTriggers` (lazy, fed by damage/overlay callbacks). Modelling both as the same element
/// lets a single push loop serve both modes.
struct FrameTrigger {
  /// Whether this push should force a keyframe — e.g. a `.lazy` overlay change, so consumers that
  /// need a keyframe can decode it immediately. Cadence-clock ticks never force one.
  let forceKeyFrame: Bool
  /// True when the previous push overshot its deadline (eager cadence only — always false for VFR).
  let overran: Bool
}

/// The `.lazy` (VFR) stimulus: an `AsyncSequence` of `FrameTrigger`s poked by `signalFrameRendered()`
/// and `signalKeyFrame()`. Triggers coalesce to the newest (`bufferingNewest(1)`) so a slow consumer
/// drops redundant frames; a keyframe request must survive that coalescing, so it is a sticky flag the
/// iterator reads-and-clears rather than a payload on a droppable trigger.
// @unchecked Sendable: `pendingKeyFrame` is mutable across threads but guarded by `lock`; the stream
// and its continuation are Sendable.
final class LazyFrameTriggers: AsyncSequence, @unchecked Sendable {
  typealias Element = FrameTrigger

  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation
  private let lock = NSLock()
  /// Whether the next pushed frame must be a keyframe. Guarded by `lock`; set by `signalKeyFrame`,
  /// read-and-cleared by the iterator, so coalescing never drops a pending keyframe.
  private var pendingKeyFrame = false

  init() {
    // The builder hands back the continuation synchronously, so the IUO is assigned before use.
    // swiftlint:disable:next implicitly_unwrapped_optional
    var continuation: AsyncStream<Void>.Continuation!
    self.stream = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
    self.continuation = continuation
  }

  /// Signal that a new frame was rendered — enqueue a push of the latest state.
  func signalFrameRendered() {
    continuation.yield(())
  }

  /// Signal that the overlay changed — mark the next push a keyframe so consumers that need a keyframe
  /// can decode the change immediately, then enqueue a push.
  func signalKeyFrame() {
    lock.lock()
    pendingKeyFrame = true
    lock.unlock()
    continuation.yield(())
  }

  /// End the stream, completing the push loop's `for await`.
  func finish() {
    continuation.finish()
  }

  /// Atomically read and clear the sticky keyframe flag.
  private func takePendingKeyFrame() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let pending = pendingKeyFrame
    pendingKeyFrame = false
    return pending
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: stream.makeAsyncIterator(), source: self)
  }

  struct AsyncIterator: nonisolated AsyncIteratorProtocol {
    var base: AsyncStream<Void>.Iterator
    let source: LazyFrameTriggers

    mutating func next() async -> FrameTrigger? {
      guard await base.next() != nil else { return nil }
      return FrameTrigger(forceKeyFrame: source.takePendingKeyFrame(), overran: false)
    }
  }
}

/// A drift-corrected frame clock for `.eager` mode. Iterating it (`for await trigger in …`) suspends
/// until the next frame deadline and yields a `FrameTrigger`, so the push loop can read as just
/// "push each tick". The iterator owns all the timing — Mach-tick deadlines, the `Task.sleep` wait,
/// drift correction, and the per-deadline overrun log — and ends (returns `nil`) when the
/// surrounding `Task` is cancelled.
///
/// Note: an overrun (a push that overshoots its deadline) is detected on the *following* `next()`,
/// when the clock finds it is already past the deadline — so at a window boundary the overrun
/// *count* can attribute to the next 5s stats window.
struct FrameCadence: AsyncSequence {
  typealias Element = FrameTrigger

  let framesPerSecond: UInt
  let logger: any FBControlCoreLogger

  func makeAsyncIterator() -> Iterator {
    Iterator(framesPerSecond: framesPerSecond, logger: logger)
  }

  struct Iterator: nonisolated AsyncIteratorProtocol {
    private let frameIntervalMach: UInt64
    private let frameIntervalNanos: UInt64
    private let machNumer: UInt64
    private let machDenom: UInt64
    private let logger: any FBControlCoreLogger
    private var nextTargetTime: UInt64
    private var firstTickPending = true

    init(framesPerSecond: UInt, logger: any FBControlCoreLogger) {
      let frameIntervalNanos = NSEC_PER_SEC / UInt64(framesPerSecond)
      var timebase = mach_timebase_info_data_t()
      mach_timebase_info(&timebase)
      self.machNumer = UInt64(timebase.numer)
      self.machDenom = UInt64(timebase.denom)
      self.frameIntervalNanos = frameIntervalNanos
      self.frameIntervalMach = frameIntervalNanos * UInt64(timebase.denom) / UInt64(timebase.numer)
      self.logger = logger
      self.nextTargetTime = mach_absolute_time() + self.frameIntervalMach
    }

    mutating func next() async -> FrameTrigger? {
      if Task.isCancelled {
        return nil
      }
      // The first tick fires immediately, before any sleep.
      if firstTickPending {
        firstTickPending = false
        return FrameTrigger(forceKeyFrame: false, overran: false)
      }

      let now = mach_absolute_time()
      var overran = false
      if now < nextTargetTime {
        // Sleep until the drift-corrected deadline. Only the remaining gap is converted to nanos.
        let remainingNanos = (nextTargetTime - now) * machNumer / machDenom
        do {
          try await Task.sleep(nanoseconds: remainingNanos)
        } catch {
          return nil // cancelled while sleeping
        }
      } else {
        // Already past the deadline — the previous push overshot the frame budget.
        overran = true
        let overrunNanos = (now - nextTargetTime) * machNumer / machDenom
        logger.log(String(format: "Frame push exceeded budget by %.1f ms (budget: %.1f ms)", Double(overrunNanos) / 1e6, Double(frameIntervalNanos) / 1e6))
      }
      nextTargetTime += frameIntervalMach
      return FrameTrigger(forceKeyFrame: false, overran: overran)
    }
  }
}

// MARK: - CadenceStats

/// Welford online mean/variance of push duration plus an overrun count, logged every 5 seconds.
struct CadenceStats {
  private let frameIntervalNanos: UInt64
  private let machToMs: Double
  private let statsIntervalMach: UInt64
  private let logger: any FBControlCoreLogger

  private var statsStartTime: UInt64
  private var pushCount: UInt64 = 0
  private var overrunCount: UInt64 = 0
  private var maxPushMach: UInt64 = 0
  private var pushMean = 0.0 // Welford mean (in Mach ticks)
  private var pushM2 = 0.0 // Welford M2 (sum of squared deviations)

  init(frameIntervalNanos: UInt64, logger: any FBControlCoreLogger) {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    self.machToMs = Double(timebase.numer) / Double(timebase.denom) / 1e6
    let statsIntervalSeconds = 5.0
    self.statsIntervalMach = UInt64(statsIntervalSeconds * 1e9) * UInt64(timebase.denom) / UInt64(timebase.numer)
    self.frameIntervalNanos = frameIntervalNanos
    self.logger = logger
    self.statsStartTime = mach_absolute_time()
  }

  mutating func record(pushDurationMach: UInt64, overran: Bool) {
    pushCount += 1
    if overran {
      overrunCount += 1
    }
    if pushDurationMach > maxPushMach {
      maxPushMach = pushDurationMach
    }
    let delta = Double(pushDurationMach) - pushMean
    pushMean += delta / Double(pushCount)
    pushM2 += delta * (Double(pushDurationMach) - pushMean)

    let now = mach_absolute_time()
    guard now - statsStartTime >= statsIntervalMach else {
      return
    }
    let avgMs = pushMean * machToMs
    let maxMs = Double(maxPushMach) * machToMs
    let stddevMs = pushCount > 1 ? sqrt(pushM2 / Double(pushCount - 1)) * machToMs : 0
    let intervalSeconds = Double(now - statsStartTime) * machToMs / 1e3
    logger.info().log(
      String(
        format: "Cadence stats (%.1fs): %llu pushes, %llu overruns, push duration avg %.1f ms / max %.1f ms, jitter stddev %.1f ms (budget: %.1f ms)",
        intervalSeconds, pushCount, overrunCount, avgMs, maxMs, stddevMs, Double(frameIntervalNanos) / 1e6))

    statsStartTime = now
    pushCount = 0
    overrunCount = 0
    maxPushMach = 0
    pushMean = 0
    pushM2 = 0
  }
}
