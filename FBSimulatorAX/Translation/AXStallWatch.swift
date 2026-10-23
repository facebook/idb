/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
import os

/// Watches one translator request, reading its target and the host's CPU ticks only once the request has waited
/// `baselineDelay`, on a queue of its own: a request answered sooner costs one timer, and a slower one is never
/// held up by the reads.
final class AXStallWatch: Sendable {
  static let baselineDelay: TimeInterval = 0.25

  /// How the watch reads, keeps time and schedules, replaceable in tests.
  struct Environment: Sendable {
    /// Runs `work` after `delay`, never before returning.
    typealias Schedule = @Sendable (_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) -> Void

    var read: @Sendable (pid_t) -> AXStallReading = { AXStallReading.read($0) }
    /// On `CLOCK_UPTIME_RAW`, the clock `AXStallReading` records.
    var now: @Sendable () -> UInt64 = { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    var schedule: Schedule = { delay, work in queue.asyncAfter(deadline: .now() + delay, execute: work) }

    private static let queue = DispatchQueue(label: "com.facebook.FBSimulatorAX.AXStallWatch", qos: .utility)
  }

  /// What the watch knew when the request ended.
  struct Findings: Sendable {
    /// When the request began, on the environment's clock.
    let requestStart: UInt64
    /// How long it waited.
    let waited: TimeInterval
    /// Nil when the request ended before the baseline was read.
    let baseline: AXStallReading?
    /// How long reading the baseline took.
    let readNanoseconds: UInt64
  }

  private struct State {
    var finished = false
    var baseline: AXStallReading?
    var readNanoseconds: UInt64 = 0
  }

  private let pid: pid_t
  private let environment: Environment
  private let requestStart: UInt64
  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Watches a request to `pid`, which is 0 when the request names no process, that begins now.
  init(pid: pid_t, environment: Environment = Environment()) {
    self.pid = pid
    self.environment = environment
    self.requestStart = environment.now()
  }

  func start() {
    environment.schedule(Self.baselineDelay) { [weak self] in self?.readBaseline() }
  }

  /// Stops the watch and returns what it read. A baseline still being read when this is called is not recorded.
  func finish() -> Findings {
    let end = environment.now()
    let (baseline, readNanoseconds) = state.withLock { state in
      state.finished = true
      return (state.baseline, state.readNanoseconds)
    }
    return Findings(
      requestStart: requestStart, waited: TimeInterval(end >= requestStart ? end - requestStart : 0) / 1_000_000_000,
      baseline: baseline, readNanoseconds: readNanoseconds)
  }

  private func readBaseline() {
    guard !state.withLock({ $0.finished }) else {
      return
    }
    let begin = environment.now()
    let reading = environment.read(pid)
    let end = environment.now()
    state.withLock { state in
      guard !state.finished else {
        return
      }
      state.baseline = reading
      state.readNanoseconds = end >= begin ? end - begin : 0
    }
  }
}
