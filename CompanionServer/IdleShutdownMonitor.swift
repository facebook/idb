/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Dispatch
import Foundation

/// Shuts a server down after a period without activity. Each `recordActivity()`
/// (a new connection or a received request) resets the countdown; if `timeout`
/// elapses with no activity, `onTimeout` is invoked exactly once.
///
/// `@unchecked Sendable`: the resettable timer is guarded by `lock`, so
/// `recordActivity()` (called on a NIO event-loop thread) and the timer's own
/// firing (on `queue`) are serialised.
final class IdleShutdownMonitor: @unchecked Sendable {
  private let timeout: TimeInterval
  private let onTimeout: @Sendable () -> Void
  private let queue = DispatchQueue(label: "com.facebook.idb.companionserver.idle")
  private let lock = NSLock()
  private var timer: DispatchSourceTimer?
  private var finished = false

  init(timeout: TimeInterval, onTimeout: @escaping @Sendable () -> Void) {
    self.timeout = timeout
    self.onTimeout = onTimeout
  }

  /// Starts the countdown. Call once, when the server is listening.
  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard timer == nil, !finished else { return }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.setEventHandler { [weak self] in self?.fire() }
    self.timer = timer
    timer.schedule(deadline: .now() + timeout)
    timer.resume()
  }

  /// Resets the countdown back to `timeout` from now.
  func recordActivity() {
    lock.lock()
    defer { lock.unlock() }
    guard let timer, !finished else { return }
    timer.schedule(deadline: .now() + timeout)
  }

  /// Cancels the countdown without invoking `onTimeout`.
  func stop() {
    lock.lock()
    defer { lock.unlock() }
    finished = true
    timer?.cancel()
    timer = nil
  }

  private func fire() {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    timer?.cancel()
    timer = nil
    lock.unlock()
    onTimeout()
  }
}
