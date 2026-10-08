/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct ResourceSamplerTests {
  @Test func captureBaselineForCurrentProcessIsPopulated() throws {
    let sample = try #require(ResourceSample.captureBaseline(pid: getpid(), processName: "self", elapsedMs: 0, timestampMs: 0))
    #expect(sample.pid == getpid())
    #expect(sample.processName == "self")
    #expect(sample.footprintBytes > 0)
    #expect(sample.residentBytes > 0)
    // Baseline has no prior reading to difference against.
    #expect(sample.cpuPct == nil)
  }

  @Test func captureBaselineForDeadProcessReturnsNil() {
    // 999_999 is above the default macOS max pid and should never be live.
    #expect(ResourceSample.captureBaseline(pid: 999_999, processName: "ghost", elapsedMs: 0, timestampMs: 0) == nil)
  }

  @Test func cpuPercentComputation() {
    // Half a core-second of CPU over one wall-second is 50%.
    #expect(abs(ResourceSample.cpuPercent(cpuDeltaNanos: 500_000_000, wallIntervalNanos: 1_000_000_000) - 50.0) < 0.0001)
    // More than one core's worth of work in the interval exceeds 100%.
    #expect(abs(ResourceSample.cpuPercent(cpuDeltaNanos: 2_000_000_000, wallIntervalNanos: 1_000_000_000) - 200.0) < 0.0001)
    // A zero interval is reported as 0 rather than dividing by zero.
    #expect(ResourceSample.cpuPercent(cpuDeltaNanos: 1_000_000, wallIntervalNanos: 0) == 0.0)
  }

  @Test func machTicksToNanosAppleSiliconTimebase() {
    #expect(ResourceSample.machTicksToNanos(3, numer: 125, denom: 3) == 125)
    #expect(ResourceSample.machTicksToNanos(240_000, numer: 125, denom: 3) == 10_000_000)
  }

  @Test func machTicksToNanosIntelTimebaseIsIdentity() {
    #expect(ResourceSample.machTicksToNanos(12_345, numer: 1, denom: 1) == 12_345)
  }

  @Test func machTicksToNanosZeroDenomIsSafe() {
    #expect(ResourceSample.machTicksToNanos(99, numer: 1, denom: 0) == 99)
  }

  @Test func machTicksToNanosZeroNumerIsZero() {
    #expect(ResourceSample.machTicksToNanos(99, numer: 0, denom: 1) == 0)
  }

  @Test func processNameForCurrentProcessIsNonEmpty() {
    let name = ResourceSampler.processName(pid: getpid())
    #expect(name != nil)
    #expect(!(name?.isEmpty ?? true))
  }

  @Test func processNameForDeadPidIsNil() {
    #expect(ResourceSampler.processName(pid: 999_999) == nil)
  }

  @Test func parentPIDForCurrentProcessIsNonZero() throws {
    let parent = try #require(ResourceSampler.parentPID(pid: getpid()))
    #expect(parent > 0)
    #expect(parent != getpid())
  }

  @Test func parentPIDForDeadPidIsNil() {
    #expect(ResourceSampler.parentPID(pid: 999_999) == nil)
  }

  @Test func processStartSecondsSince1970IsPlausible() throws {
    let started = try #require(ResourceSampler.processStartSecondsSince1970(pid: getpid()))
    let now = Int64(Date().timeIntervalSince1970)
    // One hour is generous for a test run.
    #expect(started <= now)
    #expect(started > now - 3600)
  }

  @Test func siblingPIDsUnderLaunchdIsNonEmpty() {
    // launchd always has children, whatever the test runner's own process topology.
    #expect(!ResourceSampler.siblingPIDs(under: 1).isEmpty)
  }

  @Test func siblingPIDsUnderDeadParentIsEmpty() {
    #expect(ResourceSampler.siblingPIDs(under: 999_999).isEmpty)
  }

  @Test func sampleReturnsWhenTheTargetExits() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    // Well inside the per-test time limit: a target that is never sampled outlives the sampler by
    // ending on its own, and the test fails on the missing samples rather than on the limit.
    process.arguments = ["10"]
    try process.run()
    let pid = process.processIdentifier
    let samples = Samples()

    // Ending the target only once it has been sampled stops a loaded host from letting it exit unseen.
    await ResourceSampler.sample(pid: pid, interval: .milliseconds(50), scope: .app) {
      samples.append($0)
      kill(pid, SIGTERM)
    }
    process.waitUntilExit()

    let taken = samples.all
    #expect(!taken.isEmpty, "The sampler never sampled the target before it exited on its own")
    #expect(taken.allSatisfy { $0.pid == pid })
    #expect(taken.first?.cpuPct == nil)
  }

  @Test func sampleReturnsWhenCancelled() async {
    let samples = Samples()
    // The test runner itself never exits during the test, so only cancellation can end this.
    let task = Task {
      await ResourceSampler.sample(pid: getpid(), interval: .milliseconds(50), scope: .appAndHelpers) { samples.append($0) }
    }
    try? await Task.sleep(for: .milliseconds(200))
    task.cancel()
    await task.value

    #expect(samples.all.contains { $0.pid == getpid() })
  }

  @Test func aRunningTargetWithoutAStartTimeHasNotExited() {
    #expect(!ResourceSampler.hasExited(pid: getpid(), startSeconds: nil))
  }

  @Test func aTargetWhoseStartTimeChangedHasExited() throws {
    let startSeconds = try #require(ResourceSampler.processStartSecondsSince1970(pid: getpid()))
    #expect(!ResourceSampler.hasExited(pid: getpid(), startSeconds: startSeconds))
    #expect(ResourceSampler.hasExited(pid: getpid(), startSeconds: startSeconds - 1))
  }

  @Test func aTargetThatIsGoneHasExitedWithoutAStartTime() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()

    #expect(ResourceSampler.hasExited(pid: process.processIdentifier, startSeconds: nil))
  }
}

private final class Samples: @unchecked Sendable {
  private let lock = NSLock()
  private var samples: [ResourceSample] = []

  func append(_ sample: ResourceSample) {
    lock.withLock { samples.append(sample) }
  }

  var all: [ResourceSample] {
    lock.withLock { samples }
  }
}
