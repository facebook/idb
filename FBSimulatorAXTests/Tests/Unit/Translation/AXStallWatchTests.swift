/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@testable import FBSimulatorAX
import Foundation
import Testing
import os

struct AXStallWatchTests {

  @Test func readsNothingForARequestAnsweredBeforeTheBaseline() {
    let host = FakeStallWatchHost()
    let watch = AXStallWatch(pid: 102, environment: host.environment)
    watch.start()
    host.advance(by: 100_000_000)

    let findings = watch.finish()
    host.runDue()

    #expect(findings.baseline == nil)
    #expect(findings.waited == 0.1)
    #expect(host.reads == FakeStallWatchHost.Reads())
  }

  @Test func readsTheTargetAndTheHostsTicksAtTheBaselineAndSaysWhen() throws {
    let host = FakeStallWatchHost()
    let watch = AXStallWatch(pid: 102, environment: host.environment)
    watch.start()

    #expect(host.pendingDelays == [AXStallWatch.baselineDelay])
    host.runDue()
    host.advance(by: 1_000_000_000)
    let findings = watch.finish()

    let baseline = try #require(findings.baseline)
    #expect(baseline.uptimeNanoseconds - findings.requestStart == 250_000_000)
    #expect(baseline.ticks != nil)
    #expect(findings.readNanoseconds == FakeStallWatchHost.readNanoseconds)
    #expect(findings.waited == 1.253)
    #expect(host.reads == FakeStallWatchHost.Reads(baselines: 1, pids: [102]))
    #expect(host.pendingDelays.isEmpty, "the baseline is the watch's only read")
  }

  @Test func readsNothingOnceFinishedEvenIfScheduledWorkStillRuns() {
    let host = FakeStallWatchHost()
    let watch = AXStallWatch(pid: 102, environment: host.environment)
    watch.start()
    _ = watch.finish()

    host.runDue()

    #expect(host.reads == FakeStallWatchHost.Reads())
  }

  @Test func doesNotRecordABaselineStillBeingReadWhenTheRequestEnds() {
    let host = FakeStallWatchHost()
    let watch = AXStallWatch(pid: 102, environment: host.environment)
    let midRead = OSAllocatedUnfairLock<AXStallWatch.Findings?>(initialState: nil)
    host.duringNextRead { midRead.withLock { $0 = watch.finish() } }
    watch.start()

    host.runDue()

    #expect(host.reads.baselines == 1)
    #expect(midRead.withLock { $0 }?.baseline == nil)
    #expect(watch.finish().baseline == nil, "the read that finished after the request was not kept")
  }

  @Test func readsNothingForAWatchNoLongerHeld() {
    let host = FakeStallWatchHost()
    do {
      let watch = AXStallWatch(pid: 102, environment: host.environment)
      watch.start()
    }

    host.runDue()

    #expect(host.reads == FakeStallWatchHost.Reads())
  }

  @Test func asksForTheProcessTheRequestNames() {
    let host = FakeStallWatchHost()
    let watch = AXStallWatch(pid: 0, environment: host.environment)
    watch.start()
    host.runDue()

    #expect(watch.finish().baseline?.counters == nil)
    #expect(host.reads.pids == [0])
  }
}
