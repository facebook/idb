/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@testable import FBSimulatorAX
import Foundation
import os

/// A stall watch's host whose clock moves only when the test moves it and whose scheduled work runs only when the
/// test says. It counts the baselines read; with `readsProcesses` they carry the real counters of the pid asked
/// for, otherwise none. Each sweep of its processes finds a simulator, `launchd_sim` 100 serving `udid`, whose
/// app, process 102, has used 200 ms more CPU than at the sweep before.
final class FakeStallWatchHost: Sendable {
  struct Reads: Equatable {
    var baselines = 0
    var pids: [pid_t] = []
    var sweeps = 0
  }

  static let udid = "0F3C2D1E-AAAA-4BBB-8CCC-123456789ABC"

  private struct Pending {
    let due: UInt64
    let work: @Sendable () -> Void
  }

  private struct State {
    var now: UInt64 = 10_000_000_000
    var reads = Reads()
    var pending: [Pending] = []
    var duringNextRead: (@Sendable () -> Void)?
    var duringNextSweep: (@Sendable () -> Void)?
  }

  /// How far the clock moves while a baseline is read.
  static let readNanoseconds: UInt64 = 3_000_000

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let readsProcesses: Bool

  init(readsProcesses: Bool = false) {
    self.readsProcesses = readsProcesses
  }

  var now: UInt64 { state.withLock { $0.now } }
  var reads: Reads { state.withLock { $0.reads } }
  /// How long until each piece of scheduled work is due, soonest first.
  var pendingDelays: [TimeInterval] {
    state.withLock { state in
      state.pending.map { TimeInterval($0.due - min($0.due, state.now)) / 1_000_000_000 }.sorted()
    }
  }

  var environment: AXStallWatch.Environment {
    var environment = AXStallWatch.Environment()
    environment.now = { [self] in now }
    environment.read = { [self] pid in
      let (uptime, hook) = state.withLock { state in
        state.reads.baselines += 1
        state.reads.pids.append(pid)
        defer { state.duringNextRead = nil }
        return (state.now, state.duringNextRead)
      }
      hook?()
      advance(by: Self.readNanoseconds)
      return AXStallReading(
        uptimeNanoseconds: uptime, counters: readsProcesses ? AXProcessCounters.read(pid) : nil,
        ticks: AXHostCPUTicks(user: 100, system: 100, idle: 100, nice: 0))
    }
    environment.schedule = { [self] delay, work in
      state.withLock { state in
        state.pending.append(Pending(due: state.now + UInt64(delay * 1_000_000_000), work: work))
      }
    }
    environment.scheduleSweep = environment.schedule
    environment.sweep = { [self] shouldStop in
      let (uptime, sweep, hook) = state.withLock { state in
        state.reads.sweeps += 1
        defer { state.duringNextSweep = nil }
        return (state.now, state.reads.sweeps, state.duringNextSweep)
      }
      hook?()
      guard !shouldStop() else {
        return nil
      }
      return AXHostSnapshot(
        processes: [
          100: AXHostProcess(pid: 100, ppid: 1, name: "launchd_sim", startMicroseconds: 900, cpuNanoseconds: 0),
          102: AXHostProcess(
            pid: 102, ppid: 100, name: "MobileSafari", startMicroseconds: 1_000, cpuNanoseconds: UInt64(sweep) * 200_000_000),
        ],
        ticks: nil, uptimeNanoseconds: uptime, wallMicroseconds: 5_000_000, readNanoseconds: 0)
    }
    environment.udid = { $0.pid == 100 ? Self.udid : nil }
    environment.cpuCount = 13
    return environment
  }

  func advance(by nanoseconds: UInt64) {
    state.withLock { $0.now += nanoseconds }
  }

  /// Runs `hook` in the middle of the next baseline read.
  func duringNextRead(_ hook: @escaping @Sendable () -> Void) {
    state.withLock { $0.duringNextRead = hook }
  }

  /// Runs `hook` in the middle of the next sweep, before it asks whether to stop.
  func duringNextSweep(_ hook: @escaping @Sendable () -> Void) {
    state.withLock { $0.duringNextSweep = hook }
  }

  /// Runs the work scheduled so far, soonest first, each with the clock moved on to when it is due.
  func runDue() {
    let due = state.withLock { state in
      defer { state.pending = [] }
      return state.pending.sorted { $0.due < $1.due }
    }
    for pending in due {
      state.withLock { $0.now = max($0.now, pending.due) }
      pending.work()
    }
  }
}
