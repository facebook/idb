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
/// for, otherwise none.
final class FakeStallWatchHost: Sendable {
  struct Reads: Equatable {
    var baselines = 0
    var pids: [pid_t] = []
  }

  private struct Pending {
    let due: UInt64
    let work: @Sendable () -> Void
  }

  private struct State {
    var now: UInt64 = 10_000_000_000
    var reads = Reads()
    var pending: [Pending] = []
    var duringNextRead: (@Sendable () -> Void)?
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
    return environment
  }

  func advance(by nanoseconds: UInt64) {
    state.withLock { $0.now += nanoseconds }
  }

  /// Runs `hook` in the middle of the next baseline read.
  func duringNextRead(_ hook: @escaping @Sendable () -> Void) {
    state.withLock { $0.duringNextRead = hook }
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
