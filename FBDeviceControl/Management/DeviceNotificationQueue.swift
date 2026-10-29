/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Serializes notification handlers, including callbacks that arrive reentrantly.
///
/// The thread that finds the queue idle drains it, including work other threads enqueue.
/// Handlers and their delegates must not synchronously wait for a later notification:
/// that notification cannot run until the current handler returns.
final class DeviceNotificationQueue {
  private let lock = NSLock()
  private var pending: [() -> Void] = []
  private var draining = false
  private var accepting: Bool

  init(accepting: Bool = true) {
    self.accepting = accepting
  }

  func resume() {
    lock.withLock { accepting = true }
  }

  func pause() {
    let discarded = lock.withLock {
      accepting = false
      let discarded = pending
      pending.removeAll()
      return discarded
    }
    withExtendedLifetime(discarded) {}
  }

  func enqueue(_ notification: @escaping () -> Void) {
    let shouldDrain = lock.withLock {
      guard accepting else { return false }
      pending.append(notification)
      guard !draining else { return false }
      draining = true
      return true
    }
    guard shouldDrain else { return }
    while let next = nextNotification() {
      next()
    }
  }

  private func nextNotification() -> (() -> Void)? {
    lock.withLock {
      guard !pending.isEmpty else {
        draining = false
        return nil
      }
      return pending.removeFirst()
    }
  }
}
