/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBDeviceControl
import Foundation
import Testing

final class NotificationTestBarrier: @unchecked Sendable {
  private let entered = DispatchSemaphore(value: 0)
  private let finish = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var successful = true

  var wasReleased: Bool { lock.withLock { successful } }

  func block() {
    entered.signal()
    let result = finish.wait(timeout: .now() + 5)
    finish.signal()
    lock.withLock { successful = successful && result == .success }
  }

  func waitUntilBlocked() -> Bool { entered.wait(timeout: .now() + 5) == .success }
  func release() { finish.signal() }
}

@Suite
struct DeviceNotificationQueueTests {
  private final class Harness: @unchecked Sendable {
    let queue = DeviceNotificationQueue()
    private let lock = NSLock()
    private var recorded: [Int] = []
    private var active = 0
    private var peak = 0

    var events: [Int] { lock.withLock { recorded } }
    var peakHandlers: Int { lock.withLock { peak } }

    func handle(_ value: Int, body: () -> Void = {}) {
      lock.withLock {
        active += 1
        peak = max(peak, active)
      }
      body()
      lock.withLock {
        recorded.append(value)
        active -= 1
      }
    }
  }

  private final class Capture {
    let onRelease: () -> Void
    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    deinit { onRelease() }
  }

  @Test
  func concurrentProducersRunHandlersSeriallyInAdmissionOrder() throws {
    let harness = Harness()
    let barrier = NotificationTestBarrier()
    let drained = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      harness.queue.enqueue {
        harness.handle(1) {
          barrier.block()
        }
      }
      drained.signal()
    }
    defer { barrier.release() }
    try #require(barrier.waitUntilBlocked())
    harness.queue.enqueue { harness.handle(2) }
    harness.queue.enqueue { harness.handle(3) }
    #expect(harness.events.isEmpty)
    barrier.release()
    try #require(drained.wait(timeout: .now() + 5) == .success)
    #expect(barrier.wasReleased)
    #expect(harness.events == [1, 2, 3])
    #expect(harness.peakHandlers == 1)
  }

  @Test
  func reentrantNotificationRunsAfterCurrentHandler() {
    let harness = Harness()
    harness.queue.enqueue {
      harness.handle(1) {
        harness.queue.enqueue { harness.handle(2) }
      }
    }
    #expect(harness.events == [1, 2])
    #expect(harness.peakHandlers == 1)
  }

  @Test
  func pauseDiscardsPendingWorkAndResumePreservesActiveHandler() throws {
    let harness = Harness()
    let barrier = NotificationTestBarrier()
    let drained = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      harness.queue.enqueue {
        harness.handle(1) {
          barrier.block()
        }
      }
      drained.signal()
    }
    defer { barrier.release() }
    try #require(barrier.waitUntilBlocked())
    weak var pending: Capture?
    autoreleasepool {
      let capture = Capture {
        harness.queue.enqueue { harness.handle(99) }
      }
      pending = capture
      harness.queue.enqueue { [capture] in
        withExtendedLifetime(capture) { harness.handle(2) }
      }
    }
    #expect(pending != nil)
    harness.queue.pause()
    #expect(pending == nil)
    harness.queue.enqueue { harness.handle(3) }
    harness.queue.resume()
    harness.queue.enqueue { harness.handle(4) }
    #expect(harness.events.isEmpty)
    barrier.release()
    try #require(drained.wait(timeout: .now() + 5) == .success)
    #expect(barrier.wasReleased)
    #expect(harness.events == [1, 4])
    #expect(harness.peakHandlers == 1)
  }
}
