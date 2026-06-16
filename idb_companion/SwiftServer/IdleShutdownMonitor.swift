/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import Dispatch
import FBControlCore
import Foundation

/// Shuts the companion down after a period of gRPC inactivity.
///
/// The companion is treated as idle only when no requests are in flight: the
/// countdown starts when the last in-flight request finishes (or at `start()` if
/// none are running yet) and is cancelled as soon as a new request arrives, so a
/// long-running call keeps the companion alive. When the countdown elapses with
/// nothing in flight, `onShutdownStarted` is invoked synchronously and then
/// `expired` resolves so the server can shut down.
@objc final class IdleShutdownMonitor: NSObject {

  /// Resolves once `idleTime` seconds pass with no active or newly-received requests.
  let expired: FBMutableFuture<NSNull>

  private let idleTime: TimeInterval
  private let logger: FBIDBLogger
  /// Invoked synchronously the instant idle shutdown begins, before `expired`
  /// resolves — used to release externally-visible resources (e.g. unlink the
  /// gRPC socket) without waiting for the async teardown.
  private let onShutdownStarted: (@Sendable () -> Void)?
  private let queue = DispatchQueue(label: "com.facebook.idb.IdleShutdownMonitor")
  private let lock = NSLock()

  /// Number of requests currently in flight.
  private var activeRequests = 0
  /// The pending idle timer, if armed.
  private var timer: DispatchSourceTimer?
  /// Bumped whenever the timer is armed or invalidated so a timer that fires after
  /// it has been superseded can tell it is stale and do nothing.
  private var generation = 0
  /// Set once `expired` has resolved; no further work happens afterwards.
  private var fired = false

  init(idleTime: TimeInterval, logger: FBIDBLogger, onShutdownStarted: (@Sendable () -> Void)? = nil) {
    self.idleTime = idleTime
    self.logger = logger
    self.onShutdownStarted = onShutdownStarted
    self.expired = FBMutableFuture<NSNull>()
    super.init()
  }

  /// Starts the idle countdown if nothing is in flight. Call once the server is
  /// listening so that a companion which is never used still exits.
  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard !fired, activeRequests == 0 else { return }
    armLocked()
  }

  /// Records that a request started; cancels any pending idle timer.
  func requestStarted() {
    lock.lock()
    defer { lock.unlock() }
    guard !fired else { return }
    activeRequests += 1
    invalidateLocked()
  }

  /// Records that a request finished; re-arms the idle timer once the last
  /// in-flight request completes.
  func requestEnded() {
    lock.lock()
    defer { lock.unlock() }
    guard !fired else { return }
    if activeRequests > 0 {
      activeRequests -= 1
    }
    if activeRequests == 0 {
      armLocked()
    }
  }

  // MARK: - Timer (callers must hold `lock`)

  private func armLocked() {
    generation += 1
    let armedGeneration = generation
    let newTimer = DispatchSource.makeTimerSource(queue: queue)
    newTimer.schedule(deadline: .now() + idleTime)
    newTimer.setEventHandler { [weak self] in
      self?.handleFire(generation: armedGeneration)
    }
    timer?.cancel()
    timer = newTimer
    newTimer.resume()
  }

  private func invalidateLocked() {
    generation += 1
    timer?.cancel()
    timer = nil
  }

  private func handleFire(generation armedGeneration: Int) {
    lock.lock()
    // Ignore a superseded timer (a request arrived or finished since it was
    // armed) or a duplicate fire, and never fire while a request is in flight.
    guard !fired, armedGeneration == generation, activeRequests == 0 else {
      lock.unlock()
      return
    }
    fired = true
    timer?.cancel()
    timer = nil
    lock.unlock()

    logger.info().log("No gRPC activity for \(Int(idleTime))s, companion will shut down")
    // Release externally-visible resources (the socket) synchronously, before the
    // async teardown begins, so nothing rediscovers this companion mid-shutdown.
    onShutdownStarted?()
    expired.resolve(withResult: NSNull())
  }
}
