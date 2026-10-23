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

struct AXStallProbeTests {

  // MARK: - Reading a process

  @Test func readsTheCountersOfALiveProcess() throws {
    let counters = try #require(AXProcessCounters.read(getpid()))
    #expect(counters.threads > 0)
    #expect(counters.cpuNanoseconds > 0)
    #expect(counters.threadCPU.count > 0)
    #expect(counters.startMicroseconds > 0)
    #expect(AXStallProbe.statusName(counters.status) == "runnable")
  }

  @Test func cannotReadAProcessThatDoesNotExist() {
    #expect(AXProcessCounters.read(0) == nil)
    #expect(AXProcessCounters.read(-1) == nil)
  }

  @Test func observesCPUThatTheProcessUsedDuringTheRequest() throws {
    let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let baseline = AXStallReading.read(getpid())
    Self.spin(nanoseconds: 200_000_000)
    let observation = AXStallProbe.observe(
      kind: "multiple_attribute", pid: getpid(), requestStart: start, duration: 1.5, outcome: .unanswered,
      baseline: baseline, end: AXStallEndReading.read(getpid()))

    #expect(try #require(observation.cpuMilliseconds) >= 150, "this thread spun for 200 ms of its own CPU time")
    #expect(observation.outcome == .unanswered)
    #expect(observation.processStatus == "runnable")
    #expect(try #require(observation.footprintMegabytes) > 0)
  }

  @Test func reportsAProcessThatWentAwayWithoutCounterChanges() {
    let observation = AXStallProbe.observe(
      kind: "frontmost", pid: 4321, requestStart: 0, duration: 3, outcome: .answered,
      baseline: Self.reading(at: 250_000_000, Self.counters(Self.before)), end: Self.end(nil))

    #expect(observation.cpuMilliseconds == nil)
    #expect(observation.busiestThreads == nil)
    #expect(observation.footprintMegabytes == nil)
    #expect(observation.processStatus == "unknown")
    #expect(AXStallProbe.describe(observation).contains(" process=gone "))
  }

  @Test func readsNothingIntoAProcessThatReplacedTheTargetAtItsPid() {
    let observation = AXStallProbe.observe(
      kind: "multiple_attribute", pid: 4321, requestStart: 0, duration: 2, outcome: .answered,
      baseline: Self.reading(at: 250_000_000, Self.counters(Self.before, started: 1_000)),
      end: Self.end(Self.counters(Self.after, started: 2_000)))

    #expect(observation.targetReplaced)
    #expect(observation.cpuMilliseconds == nil)
    #expect(observation.contextSwitches == nil)
    #expect(observation.busiestThreads == nil)
    #expect(observation.threads == 5, "the process at the end is still described")
    #expect(AXStallProbe.describe(observation).contains(" process=replaced "))
  }

  @Test func takesTheChangeInAWrappedCounterModuloItsWidth() {
    let observation = AXStallProbe.observe(
      kind: "multiple_attribute", pid: 4321, requestStart: 0, duration: 2, outcome: .answered,
      baseline: Self.reading(at: 250_000_000, Self.counters(Self.before, contextSwitches: UInt32.max - 5)),
      end: Self.end(Self.counters(Self.after, contextSwitches: 10)))

    #expect(observation.contextSwitches == 16)
  }

  @Test func saysWhenTheBaselineWasReadAndMeasuresTheHostFromThenOn() throws {
    let observation = AXStallProbe.observe(
      kind: "multiple_attribute", pid: 4321, requestStart: 10_000_000_000, duration: 2, outcome: .answered,
      baseline: Self.reading(at: 10_400_000_000, nil, ticks: AXHostCPUTicks(user: 1000, system: 500, idle: 8000, nice: 0)),
      end: Self.end(nil, ticks: AXHostCPUTicks(user: 1700, system: 700, idle: 8100, nice: 0)),
      baselineReadNanoseconds: 180_000, inlineNanoseconds: 41_500)
    let line = AXStallProbe.describe(observation)

    #expect(observation.probeInlineMicroseconds == 41)
    #expect(line.contains(" probe_us=180 probe_inline_us=41 "))
    #expect(observation.baselineMilliseconds == 400)
    #expect(observation.hostBusyPercent == 90)
    #expect(observation.probeMicroseconds == 180)
    #expect(line.contains(" baseline_ms=400 "))
    #expect(line.hasSuffix(" host_busy_pct=90 sweep_us=0"), "no window: the host's processes were not read twice")
    #expect(!line.contains("process=gone"), "a request with no target read at the baseline is not reported gone")
  }

  @Test func reportsNoBaselineForARequestThatEndedBeforeOne() {
    let observation = AXStallProbe.observe(
      kind: "frontmost", pid: 4321, requestStart: 0, duration: 1.2, outcome: .answered, baseline: nil,
      end: Self.end(Self.counters(Self.after)))
    let line = AXStallProbe.describe(observation)

    #expect(observation.baselineMilliseconds == nil)
    #expect(observation.hostBusyPercent == nil)
    #expect(!observation.probedBefore)
    #expect(!line.contains("baseline_ms="))
    #expect(!line.contains("cpu_ms="))
    #expect(!line.contains("process="))
    #expect(line.contains(" running_threads=1 threads=5 "))
  }

  @Test func namesEveryThreadRunState() {
    #expect(AXStallProbe.runState(TH_STATE_RUNNING) == "running")
    #expect(AXStallProbe.runState(TH_STATE_STOPPED) == "stopped")
    #expect(AXStallProbe.runState(TH_STATE_WAITING) == "waiting")
    #expect(AXStallProbe.runState(TH_STATE_UNINTERRUPTIBLE) == "uninterruptible")
    #expect(AXStallProbe.runState(TH_STATE_HALTED) == "halted")
    #expect(AXStallProbe.runState(42) == "state42")
  }

  @Test func namesEveryProcessStatus() {
    #expect(AXStallProbe.statusName(UInt32(SIDL)) == "idle")
    #expect(AXStallProbe.statusName(UInt32(SRUN)) == "runnable")
    #expect(AXStallProbe.statusName(UInt32(SSLEEP)) == "sleeping")
    #expect(AXStallProbe.statusName(UInt32(SSTOP)) == "stopped")
    #expect(AXStallProbe.statusName(UInt32(SZOMB)) == "zombie")
    #expect(AXStallProbe.statusName(9) == "status9")
  }

  // MARK: - Threads

  @Test func ranksThreadsByTheCPUTheyUsedBetweenTheReads() {
    let ranked = AXThreadUse.ranked(before: Self.before, after: Self.after)

    #expect(ranked.map(\.id) == [0x10, 0x50, 0x20, 0x40, 0x60])
    #expect(ranked.map(\.cpuMilliseconds) == [1500, 900, 400, 200, 0])
    #expect(ranked.map(\.rank) == [1, 2, 3, 4, 5])
  }

  @Test func ranksNothingWithoutBothReads() {
    #expect(AXThreadUse.ranked(before: [], after: Self.after).isEmpty)
    #expect(AXThreadUse.ranked(before: Self.before, after: []).isEmpty)
  }

  @Test func observesTheBusiestThreadsAndTheMainThread() {
    let observation = AXStallProbe.observe(
      kind: "multiple_attribute", pid: 4321, requestStart: 0, duration: 2, outcome: .answered,
      baseline: Self.reading(at: 250_000_000, Self.counters(Self.before)), end: Self.end(Self.counters(Self.after)))

    #expect(observation.busiestThreads?.map(\.id) == [0x10, 0x50, 0x20])
    #expect(observation.mainThread?.id == 0x10)
    #expect(observation.mainThread?.rank == 1)
    #expect(observation.mainThreadCPUMilliseconds == 1500)
  }

  @Test func reportsNoBusyThreadsForAProcessThatDidNotRun() {
    let observation = AXStallProbe.observe(
      kind: "multiple_attribute", pid: 4321, requestStart: 0, duration: 3, outcome: .unanswered,
      baseline: Self.reading(at: 250_000_000, Self.counters(Self.before)), end: Self.end(Self.counters(Self.before)))

    #expect(observation.busiestThreads?.isEmpty == true)
    #expect(observation.mainThread?.cpuMilliseconds == 0)
    #expect(AXStallProbe.describe(observation).contains(" busy_threads=[] main_thread_cpu_ms=0 main_thread_rank=1 "))
  }

  @Test func leavesOutBusyThreadsWhenTheThreadsCouldNotBeListedAtTheBaseline() {
    let observation = AXStallProbe.observe(
      kind: "multiple_attribute", pid: 4321, requestStart: 0, duration: 3, outcome: .answered,
      baseline: Self.reading(at: 250_000_000, Self.counters([])), end: Self.end(Self.counters(Self.after)))
    let line = AXStallProbe.describe(observation)

    #expect(observation.busiestThreads == nil)
    #expect(!line.contains("busy_threads="))
    #expect(!line.contains("main_thread_"))
  }

  @Test func attributesCPUToTheThreadThatUsedIt() throws {
    let earlier = AXThreadCPU.read(getpid(), expecting: 512)
    let started = DispatchSemaphore(value: 0)
    let spin = DispatchSemaphore(value: 0)
    let spun = DispatchSemaphore(value: 0)
    let finish = DispatchSemaphore(value: 0)
    Thread {
      pthread_setname_np("ax-stall-probe-spinner")
      started.signal()
      spin.wait()
      // Until the thread itself has used 200 ms of CPU, however long a loaded host takes to give it that.
      Self.spin(nanoseconds: 200_000_000)
      spun.signal()
      finish.wait()
    }.start()
    defer { finish.signal() }
    started.wait()
    let before = try #require(AXProcessCounters.read(getpid()))
    spin.signal()
    spun.wait()
    let after = try #require(AXProcessCounters.read(getpid()))

    let spinner = try #require(
      AXThreadUse.ranked(before: before.threadCPU, after: after.threadCPU).first { $0.name == "ax-stall-probe-spinner" })
    #expect(spinner.cpuMilliseconds >= 150)
    #expect(spinner.cpuMilliseconds < 1000)
    // A thread started after a read is listed after the threads that read saw: the oldest, main thread leads.
    #expect(before.threadCPU.first?.id == earlier.first?.id)
    #expect(before.threadCPU.first?.id != spinner.id)
  }

  @Test func labelsThreadsAsOneWordEach() {
    let main = AXThreadUse(id: 0x1f, name: "", cpuMilliseconds: 12, runState: TH_STATE_RUNNING, rank: 1)
    let unnamed = AXThreadUse(id: 0x2a, name: "", cpuMilliseconds: 3, runState: TH_STATE_WAITING, rank: 2)
    let spaced = AXThreadUse(
      id: 0x3b, name: "JavaScriptCore bmalloc, scavenger|[1]", cpuMilliseconds: 1, runState: TH_STATE_WAITING, rank: 3)

    #expect(AXStallProbe.label(main, isMain: true) == "main|0x1f:12")
    #expect(AXStallProbe.label(unnamed, isMain: false) == "-|0x2a:3")
    #expect(AXStallProbe.label(spaced, isMain: false) == "JavaScriptCore_bmalloc__scavenger__1_|0x3b:1")
  }

  // MARK: - Host

  @Test func readsTheHostItRunsOn() {
    let host = AXHostFacts.current
    #expect(host.cpuCount == ProcessInfo.processInfo.processorCount)
    #expect(host.memoryGigabytes == Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()))
    #expect(host.model != "unknown" && !host.model.isEmpty)
    #expect(host.cpu != "unknown" && !host.cpu.isEmpty)
  }

  @Test func readsTheHostsTicksAndMemoryWithoutPrivileges() throws {
    #expect(AXHostCPUTicks.read() != nil)
    let memory = AXMemoryState.read()
    #expect(["normal", "warn", "critical"].contains(try #require(memory.pressure)))
    #expect((0...100).contains(try #require(memory.freePercent)))
    #expect(memory.swapUsedMegabytes != nil)
  }

  @Test func measuresTheBusyShareOfTheHostsTicksAcrossAWrap() {
    let before = AXHostCPUTicks(user: UInt32.max - 9, system: 500, idle: 8000, nice: 0)
    let after = AXHostCPUTicks(user: 90, system: 500, idle: 8100, nice: 0)

    #expect(after.busyShare(since: before) == 0.5)
    #expect(after.busyShare(since: after) == nil)
  }

  @Test func namesEveryMemoryPressureLevel() {
    #expect(AXMemoryState.pressureName(1) == "normal")
    #expect(AXMemoryState.pressureName(2) == "warn")
    #expect(AXMemoryState.pressureName(4) == "critical")
    #expect(AXMemoryState.pressureName(8) == "level8")
  }

  @Test func describesTheRequestTheTargetAndTheHostOnOneLine() {
    let observation = AccessibilityStallObservation(
      requestKind: "multiple_attribute", pid: 4321, duration: 2.5, outcome: .answered, baselineMilliseconds: 250,
      cpuMilliseconds: 2100, contextSwitches: 9000, syscalls: 40000, pageins: 12, runningThreads: 3, threads: 70,
      processStatus: "runnable", hostLoad: 81.34, hostBusyPercent: 97,
      busiestThreads: [AXThreadUse(id: 0x10, name: "", cpuMilliseconds: 1500, runState: TH_STATE_RUNNING, rank: 1)],
      mainThread: AXThreadUse(id: 0x10, name: "", cpuMilliseconds: 1500, runState: TH_STATE_RUNNING, rank: 1),
      footprintMegabytes: 812, residentMegabytes: 640,
      host: AXHostFacts(name: "sim host", model: "VirtualMac2,1", cpu: "Apple M4 (Virtual)", cpuCount: 13, memoryGigabytes: 48),
      memory: AXMemoryState(pressure: "warn", freePercent: 12, swapUsedMegabytes: 2048), probeMicroseconds: 180,
      probeInlineMicroseconds: 40, sweepMicroseconds: 0, probedBefore: true, targetReplaced: false, hostActivity: nil)

    let expected: [String] = [
      "ax_stall_probe kind=multiple_attribute pid=4321 duration_ms=2500 outcome=answered baseline_ms=250 cpu_ms=2100",
      "context_switches=9000 syscalls=40000 pageins=12 running_threads=3 threads=70",
      "busy_threads=[main|0x10:1500] main_thread_cpu_ms=1500 main_thread_rank=1 main_thread_state=running",
      "footprint_mb=812 resident_mb=640 host_load=81.3 ax_host=sim_host hw_model=VirtualMac2,1",
      "cpu=Apple_M4_(Virtual) ncpu=13 mem_gb=48 memory_pressure=warn mem_free_pct=12 swap_used_mb=2048",
      "probe_us=180 probe_inline_us=40 process_status=runnable host_busy_pct=97 sweep_us=0",
    ]
    #expect(AXStallProbe.describe(observation) == expected.joined(separator: " "))
  }

  @Test func endsTheLineWithWhatTheHostsProcessesDid() {
    let activity = AXHostActivityTests.activity(ownUDID: AXHostActivityTests.udidA)
    let observation = AXStallProbe.observe(
      kind: "frontmost", pid: 4321, requestStart: 0, duration: 2.5, outcome: .answered, baseline: nil,
      end: Self.end(nil), host: activity, sweepNanoseconds: 6_400_000)
    let line = AXStallProbe.describe(observation)

    #expect(line.hasSuffix(" sweep_us=6400 " + activity.logFields.joined(separator: " ")))
    #expect(observation.hostWindowStartMilliseconds == 250)
    #expect(observation.hostWindowBusyPercent == 92)
    #expect(observation.userCPUMilliseconds == 4310)
    #expect(observation.activeSimulators == 2)
    #expect(observation.ownSimulatorCPUMilliseconds == 2950)
    #expect(observation.otherSimulatorsCPUMilliseconds == 950)
  }

  // MARK: - Fixtures

  /// A main thread that used 1.5 s, one that started meanwhile, one that exited, one at an exited thread's
  /// address and one that did not run.
  private static let before = [
    AXThreadCPU(id: 0x10, name: "", cpuNanoseconds: 4_000_000_000, runState: TH_STATE_RUNNING),
    AXThreadCPU(id: 0x20, name: "com.apple.uikit.eventfetch-thread", cpuNanoseconds: 50_000_000, runState: TH_STATE_WAITING),
    AXThreadCPU(id: 0x30, name: "exited", cpuNanoseconds: 9_000_000_000, runState: TH_STATE_WAITING),
    AXThreadCPU(id: 0x40, name: "reused", cpuNanoseconds: 700_000_000, runState: TH_STATE_WAITING),
    AXThreadCPU(id: 0x60, name: "idle", cpuNanoseconds: 30_000_000, runState: TH_STATE_WAITING),
  ]
  private static let after = [
    AXThreadCPU(id: 0x10, name: "", cpuNanoseconds: 5_500_000_000, runState: TH_STATE_RUNNING),
    AXThreadCPU(id: 0x20, name: "com.apple.uikit.eventfetch-thread", cpuNanoseconds: 450_000_000, runState: TH_STATE_WAITING),
    AXThreadCPU(id: 0x40, name: "reused", cpuNanoseconds: 200_000_000, runState: TH_STATE_RUNNING),
    AXThreadCPU(id: 0x60, name: "idle", cpuNanoseconds: 30_000_000, runState: TH_STATE_WAITING),
    AXThreadCPU(id: 0x50, name: "started", cpuNanoseconds: 900_000_000, runState: TH_STATE_RUNNING),
  ]

  private static func counters(
    _ threads: [AXThreadCPU], started: UInt64 = 1_000, contextSwitches: UInt32 = 0
  ) -> AXProcessCounters {
    AXProcessCounters(
      cpuNanoseconds: threads.reduce(0) { $0 + $1.cpuNanoseconds }, contextSwitches: contextSwitches, syscalls: 0,
      pageins: 0, threads: Int32(threads.count), runningThreads: 1, startMicroseconds: started, status: UInt32(SRUN),
      threadCPU: threads)
  }

  private static func reading(
    at uptime: UInt64, _ counters: AXProcessCounters?, ticks: AXHostCPUTicks? = nil
  ) -> AXStallReading {
    AXStallReading(uptimeNanoseconds: uptime, counters: counters, ticks: ticks)
  }

  private static func end(_ counters: AXProcessCounters?, ticks: AXHostCPUTicks? = nil) -> AXStallEndReading {
    AXStallEndReading(
      reading: reading(at: 2_000_000_000, counters, ticks: ticks), usage: counters.map { _ in rusage_info_v4() },
      hostLoad: nil, memory: AXMemoryState(pressure: nil, freePercent: nil, swapUsedMegabytes: nil))
  }

  /// Until this thread has used `nanoseconds` of CPU, however long a loaded host takes to give it that.
  private static func spin(nanoseconds: UInt64) {
    var value = 1.0
    let deadline = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) + nanoseconds
    while clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) < deadline {
      value = value.squareRoot() + 1
    }
    withExtendedLifetime(value) {}
  }
}
