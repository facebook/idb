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
///
/// From the baseline on, every `sweepPeriod` while the request still waits, the watch also reads every process of
/// the host, on another queue so a slow read of them never delays another request's baseline, and compares the
/// latest read with the first: what each simulator used during the wait.
final class AXStallWatch: Sendable {
  static let baselineDelay: TimeInterval = 0.25
  static let sweepPeriod: TimeInterval = 1
  static let maxSweeps = 10

  /// How the watch reads, keeps time and schedules, replaceable in tests.
  struct Environment: Sendable {
    /// Runs `work` after `delay`, never before returning.
    typealias Schedule = @Sendable (_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) -> Void

    var read: @Sendable (pid_t) -> AXStallReading = { AXStallReading.read($0) }
    /// On `CLOCK_UPTIME_RAW`, the clock `AXStallReading` records.
    var now: @Sendable () -> UInt64 = { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    var schedule: Schedule = { delay, work in queue.asyncAfter(deadline: .now() + delay, execute: work) }
    /// Reads the host's processes, stopping when told to; nil when it stopped.
    var sweep: @Sendable (_ shouldStop: () -> Bool) -> AXHostSnapshot? = { AXHostSampler.snapshot(shouldStop: $0) }
    var udid: @Sendable (AXHostProcess) -> String? = { AXSimulatorDevices.udid(of: $0) }
    var cpuCount = AXHostFacts.current.cpuCount
    var scheduleSweep: Schedule = { delay, work in sweepQueue.asyncAfter(deadline: .now() + delay, execute: work) }

    private static let queue = DispatchQueue(label: "com.facebook.FBSimulatorAX.AXStallWatch", qos: .utility)
    private static let sweepQueue = DispatchQueue(label: "com.facebook.FBSimulatorAX.AXStallWatch.sweep", qos: .utility)
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
    /// From the first sweep to the latest; nil until two have been read.
    let activity: AXHostActivity?
    /// How long this watch's sweeps took.
    let sweepNanoseconds: UInt64
  }

  private struct State {
    var finished = false
    var baseline: AXStallReading?
    var readNanoseconds: UInt64 = 0
    var firstSweep: AXHostSnapshot?
    var sweeps = 0
    var activity: AXHostActivity?
    var sweepNanoseconds: UInt64 = 0
  }

  private let pid: pid_t
  private let ownUDID: String?
  private let environment: Environment
  private let requestStart: UInt64
  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Watches a request to `pid`, which is 0 when the request names no process, made to the simulator serving
  /// `ownUDID`, that begins now.
  init(pid: pid_t, ownUDID: String? = nil, environment: Environment = Environment()) {
    self.pid = pid
    self.ownUDID = ownUDID
    self.environment = environment
    self.requestStart = environment.now()
  }

  func start() {
    environment.schedule(Self.baselineDelay) { [weak self] in self?.readBaseline() }
  }

  /// Stops the watch and returns what it read. A baseline still being read when this is called is not recorded.
  func finish() -> Findings {
    let end = environment.now()
    let read = state.withLock { state in
      state.finished = true
      return state
    }
    return Findings(
      requestStart: requestStart, waited: TimeInterval(end >= requestStart ? end - requestStart : 0) / 1_000_000_000,
      baseline: read.baseline, readNanoseconds: read.readNanoseconds, activity: read.activity,
      sweepNanoseconds: read.sweepNanoseconds)
  }

  private func readBaseline() {
    guard !state.withLock({ $0.finished }) else {
      return
    }
    let begin = environment.now()
    let reading = environment.read(pid)
    let end = environment.now()
    let recorded = state.withLock { state in
      guard !state.finished else {
        return false
      }
      state.baseline = reading
      state.readNanoseconds = end >= begin ? end - begin : 0
      return true
    }
    if recorded {
      environment.scheduleSweep(0) { [weak self] in self?.sweep() }
    }
  }

  private func sweep() {
    guard let first = state.withLock({ $0.finished ? nil : Optional($0.firstSweep) }) else {
      return
    }
    let begin = environment.now()
    let snapshot = environment.sweep { [state] in state.withLock { $0.finished } }
    let activity = snapshot.flatMap { snapshot in
      first.map {
        AXHostActivity.between(
          $0, snapshot, requestStart: requestStart, ownUDID: ownUDID, target: pid, cpuCount: environment.cpuCount,
          udid: environment.udid)
      }
    }
    let end = environment.now()
    let more = state.withLock { state in
      guard !state.finished, let snapshot else {
        return false
      }
      if state.firstSweep == nil {
        state.firstSweep = snapshot
      } else {
        state.activity = activity
      }
      state.sweeps += 1
      state.sweepNanoseconds += end >= begin ? end - begin : 0
      return state.sweeps < Self.maxSweeps
    }
    if more {
      environment.scheduleSweep(Self.sweepPeriod) { [weak self] in self?.sweep() }
    }
  }
}
