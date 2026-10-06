/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Shares one following of a simulator's display configurations between every subscriber. The first
/// subscriber starts it and the last to leave stops it; a subscriber that joins late starts from the most
/// recent configuration. The following polls as often as the most demanding current subscriber asks.
// SAFETY: `state` guards the subscribers, the following task and the last configuration. `delivery` serialises
// yields, so a late subscriber's replay cannot overtake a newer configuration.
// patternlint-disable-next-line unchecked-sendable
final class DisplayConfigurationFollower: @unchecked Sendable {
  /// Yielding to a stream whose consumer is being cancelled waits on that consumer, and cancellation runs
  /// `onTermination`, which takes `state`. So nothing yields while holding `state`.
  private let state = NSLock()
  private let delivery = NSLock()
  private var subscribers: [UUID: (continuation: AsyncStream<SimulatorDisplayConfiguration>.Continuation, interval: Duration)] = [:]
  private var following: Task<Void, Never>?
  /// Only kept while someone subscribes, so a replay is never older than the subscription it joins.
  private var last: SimulatorDisplayConfiguration?

  /// The shortest polling interval any current subscriber asked for.
  var interval: Duration? {
    state.lock()
    defer { state.unlock() }
    return subscribers.values.map(\.interval).min()
  }

  /// `start` runs only when nothing is following yet. Whatever it observes reaches subscribers through `offer`.
  func subscribe(polling interval: Duration, start: () -> Task<Void, Never>) -> AsyncStream<SimulatorDisplayConfiguration> {
    let (stream, continuation) = AsyncStream<SimulatorDisplayConfiguration>.makeStream()
    let id = UUID()
    delivery.lock()
    defer { delivery.unlock() }
    state.lock()
    subscribers[id] = (continuation, interval)
    let replay = last
    if following == nil {
      following = start()
    }
    state.unlock()
    continuation.onTermination = { [weak self] _ in self?.unsubscribe(id) }
    if let replay {
      continuation.yield(replay)
    }
    return stream
  }

  /// Every configuration the tracker observes, whoever read it, so subscribers see a change as soon as any reader does.
  func offer(_ configuration: SimulatorDisplayConfiguration) {
    delivery.lock()
    defer { delivery.unlock() }
    state.lock()
    guard !subscribers.isEmpty, configuration != last else {
      state.unlock()
      return
    }
    last = configuration
    let recipients = subscribers.values.map(\.continuation)
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
    last = nil
    state.unlock()
    stopping.cancel()
  }
}
