/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Whether a read was cancelled, and the wait that stops when it is.
///
/// A read's translator requests are synchronous, on a dispatch queue rather than a task, so they cannot see
/// their task's cancellation; this is how it reaches them. Cancelling wakes any request in flight at once,
/// and the read stops before its next request.
// SAFETY: `cancelled` and `waiters` are only read or written under `lock`.
// patternlint-disable-next-line unchecked-sendable
final class AXReadCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var waiters: [DispatchSemaphore] = []

  var isCancelled: Bool { lock.withLock { cancelled } }

  func cancel() {
    let woken: [DispatchSemaphore] = lock.withLock {
      cancelled = true
      defer { waiters = [] }
      return waiters
    }
    woken.forEach { $0.signal() }
  }

  /// `body`'s result, unless the read is cancelled first, in which case this throws `CancellationError`
  /// straight away and `body` finishes unobserved.
  func wait<T>(for body: @escaping () -> T) throws -> T {
    let finished = DispatchSemaphore(value: 0)
    let box = AXResultBox<T>()
    let registered: Bool = lock.withLock {
      guard !cancelled else { return false }
      waiters.append(finished)
      return true
    }
    guard registered else { throw CancellationError() }
    DispatchQueue.global(qos: .userInitiated).async {
      box.value = body()
      finished.signal()
    }
    finished.wait()
    lock.withLock { waiters.removeAll { $0 === finished } }
    guard let value = box.value, !isCancelled else { throw CancellationError() }
    return value
  }
}
