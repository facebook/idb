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
///
/// Triggers are paced to at most `maximumFramesPerSecond`: a trigger that arrives sooner than that
/// after the last one is held, not dropped, until the interval has passed, so the newest content is
/// still pushed but never twice within one display interval — a signal that lands mid-push would
/// otherwise be pushed the instant the push returns, and a 120 Hz display would otherwise cost 120
/// encodes a second for viewers that show 60.
// @unchecked Sendable: `pendingKeyFrame` is mutable across threads but guarded by `lock`; the stream
// and its continuation are Sendable.
final class LazyFrameTriggers: AsyncSequence, @unchecked Sendable {
  typealias Element = FrameTrigger

  /// The default pace: one push per 60 Hz display interval.
  static let defaultMaximumFramesPerSecond: UInt = 60

  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation
  private let lock = NSLock()
  /// Whether the next pushed frame must be a keyframe. Guarded by `lock`; set by `signalKeyFrame`,
  /// read-and-cleared by the iterator, so coalescing never drops a pending keyframe.
  private var pendingKeyFrame = false
  fileprivate let minimumIntervalMach: UInt64

  init(maximumFramesPerSecond: UInt = LazyFrameTriggers.defaultMaximumFramesPerSecond) {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    self.minimumIntervalMach = (NSEC_PER_SEC / UInt64(maximumFramesPerSecond)) * UInt64(timebase.denom) / UInt64(timebase.numer)
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
    private var lastTriggerMach: UInt64 = 0

    init(base: AsyncStream<Void>.Iterator, source: LazyFrameTriggers) {
      self.base = base
      self.source = source
    }

    mutating func next() async -> FrameTrigger? {
      guard await base.next() != nil else { return nil }
      let earliest = lastTriggerMach + source.minimumIntervalMach
      if mach_absolute_time() < earliest {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        guard (try? await StrictTimer.wait(untilUptimeNanoseconds: earliest * UInt64(timebase.numer) / UInt64(timebase.denom))) != nil else {
          return nil // cancelled while pacing
        }
      }
      lastTriggerMach = mach_absolute_time()
      return FrameTrigger(forceKeyFrame: source.takePendingKeyFrame(), overran: false)
    }
  }
}

/// A drift-corrected frame clock for `.eager` mode. Iterating it (`for await trigger in …`) suspends
/// until the next frame deadline and yields a `FrameTrigger`, so the push loop can read as just
/// "push each tick". The iterator owns all the timing — Mach-tick deadlines, the `Task.sleep` wait
/// and drift correction — and ends (returns `nil`) when the surrounding `Task` is cancelled.
///
/// An overrun (a push that overshoots its deadline) is detected on the *following* `next()`, when
/// the clock finds it is already past the deadline. That tick fires immediately and the deadlines
/// the stall consumed are skipped, so a stall of N intervals costs one late frame rather than N
/// back-to-back copies of it. `CadenceStats` reports the overrun count; at a window boundary the
/// count can attribute to the next 5s stats window.
struct FrameCadence: AsyncSequence {
  typealias Element = FrameTrigger

  let framesPerSecond: UInt

  func makeAsyncIterator() -> Iterator {
    Iterator(framesPerSecond: framesPerSecond)
  }

  struct Iterator: nonisolated AsyncIteratorProtocol {
    private let frameIntervalMach: UInt64
    private let machNumer: UInt64
    private let machDenom: UInt64
    private var nextTargetTime: UInt64
    private var firstTickPending = true

    init(framesPerSecond: UInt) {
      let frameIntervalNanos = NSEC_PER_SEC / UInt64(framesPerSecond)
      var timebase = mach_timebase_info_data_t()
      mach_timebase_info(&timebase)
      self.machNumer = UInt64(timebase.numer)
      self.machDenom = UInt64(timebase.denom)
      self.frameIntervalMach = frameIntervalNanos * UInt64(timebase.denom) / UInt64(timebase.numer)
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
        do {
          try await StrictTimer.wait(untilUptimeNanoseconds: nextTargetTime * machNumer / machDenom)
        } catch {
          return nil // cancelled while waiting
        }
      } else {
        // Already past the deadline — the previous push overshot the frame budget. Skip the
        // deadlines the stall consumed so the grid stays aligned but no catch-up burst follows.
        overran = true
        let missed = (now - nextTargetTime) / frameIntervalMach
        nextTargetTime += missed * frameIntervalMach
      }
      nextTargetTime += frameIntervalMach
      return FrameTrigger(forceKeyFrame: false, overran: overran)
    }
  }
}

// MARK: - StrictTimer

/// A wait that fires on its deadline. `Task.sleep`, `usleep` and `mach_wait_until` are all subject to
/// timer coalescing, which for a process at utility or background QoS — a recorder launched by a
/// test harness or a daemon — lands the wake-up 25–40 ms late, most of a 30 fps frame budget. Only a
/// dispatch timer with the `.strict` flag opts out of coalescing (measured 0.1 ms median lateness
/// where `Task.sleep` measured 25 ms on the same host).
enum StrictTimer {
  private static let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.frame-cadence", qos: .userInteractive)

  /// Resumes exactly once, whichever of the timer's handlers runs first.
  // SAFETY: `continuation` is only read and written under `lock`, and `resume` takes it out under
  // the lock so a second call finds nil.
  // patternlint-disable-next-line unchecked-sendable
  private final class Resumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
      self.continuation = continuation
    }

    func resume(_ result: Result<Void, Error>) {
      lock.lock()
      let continuation = self.continuation
      self.continuation = nil
      lock.unlock()
      continuation?.resume(with: result)
    }
  }

  /// Suspends until the uptime deadline (`mach_absolute_time` converted to nanoseconds), throwing
  /// `CancellationError` if the task is cancelled first.
  static func wait(untilUptimeNanoseconds deadline: UInt64) async throws {
    let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let resumer = Resumer(continuation)
        timer.setEventHandler {
          resumer.resume(.success(()))
          timer.cancel()
        }
        timer.setCancelHandler {
          resumer.resume(.failure(CancellationError()))
        }
        timer.schedule(deadline: DispatchTime(uptimeNanoseconds: deadline), leeway: .nanoseconds(0))
        timer.resume()
        // A cancellation that raced the setup above has no timer to cancel yet; honour it now.
        if Task.isCancelled {
          timer.cancel()
        }
      }
    } onCancel: {
      timer.cancel()
    }
  }
}

// MARK: - CadenceStats

/// Welford online mean/variance of push duration plus an overrun count, logged every 5 seconds.
struct CadenceStats {
  private let frameIntervalNanos: UInt64
  private let machToMs: Double
  private let statsIntervalMach: UInt64
  private let logger: any ControlCoreLogger

  private var statsStartTime: UInt64
  private var pushCount: UInt64 = 0
  private var overrunCount: UInt64 = 0
  private var maxPushMach: UInt64 = 0
  private var pushMean = 0.0 // Welford mean (in Mach ticks)
  private var pushM2 = 0.0 // Welford M2 (sum of squared deviations)

  init(frameIntervalNanos: UInt64, logger: any ControlCoreLogger) {
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
