/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Shares one following of a simulator's display configurations between every subscriber. The first
/// subscriber starts it and the last to leave stops it; a subscriber that joins late starts from the most
/// recent configuration.
// SAFETY: `state` guards the subscribers, the following task and the last configuration. `delivery` serialises
// yields, so a late subscriber's replay cannot overtake a newer configuration.
// patternlint-disable-next-line unchecked-sendable
final class DisplayConfigurationFollower: @unchecked Sendable {
  typealias Publish = @Sendable (SimulatorDisplayConfiguration) -> Void

  /// Yielding to a stream whose consumer is being cancelled waits on that consumer, and cancellation runs
  /// `onTermination`, which takes `state`. So nothing yields while holding `state`.
  private let state = NSLock()
  private let delivery = NSLock()
  private var subscribers: [UUID: AsyncStream<SimulatorDisplayConfiguration>.Continuation] = [:]
  private var following: Task<Void, Never>?
  /// Distinguishes the current following from a cancelled one that has not yet stopped publishing.
  private var epoch: UInt64 = 0
  private var last: SimulatorDisplayConfiguration?

  /// `start` runs only when nothing is following yet, and publishes each configuration it observes.
  func subscribe(start: (@escaping Publish) -> Task<Void, Never>) -> AsyncStream<SimulatorDisplayConfiguration> {
    let (stream, continuation) = AsyncStream<SimulatorDisplayConfiguration>.makeStream()
    let id = UUID()
    delivery.lock()
    defer { delivery.unlock() }
    state.lock()
    subscribers[id] = continuation
    let replay = last
    if following == nil {
      let epoch = epoch
      following = start { [weak self] configuration in self?.publish(configuration, epoch: epoch) }
    }
    state.unlock()
    continuation.onTermination = { [weak self] _ in self?.unsubscribe(id) }
    if let replay {
      continuation.yield(replay)
    }
    return stream
  }

  private func publish(_ configuration: SimulatorDisplayConfiguration, epoch: UInt64) {
    delivery.lock()
    defer { delivery.unlock() }
    state.lock()
    guard epoch == self.epoch, configuration != last else {
      state.unlock()
      return
    }
    last = configuration
    let recipients = Array(subscribers.values)
    state.unlock()
    for recipient in recipients {
      recipient.yield(configuration)
    }
  }

  private func unsubscribe(_ id: UUID) {
    state.lock()
    subscribers[id] = nil
    guard subscribers.isEmpty, let stopping = following else {
      state.unlock()
      return
    }
    following = nil
    epoch += 1
    last = nil
    state.unlock()
    stopping.cancel()
  }
}
