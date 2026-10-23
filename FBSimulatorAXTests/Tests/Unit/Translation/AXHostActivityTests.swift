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

struct AXHostActivityTests {

  // MARK: - Reading the host

  @Test func readsTheProcessesOfItsOwnUser() throws {
    let snapshot = try #require(AXHostSnapshot.read())
    let own = try #require(snapshot.processes[getpid()])
    #expect(own.ppid == getppid())
    #expect(own.startMicroseconds > 0)
    #expect(own.cpuNanoseconds > 0)
    #expect(snapshot.ticks != nil)
  }

  @Test func stopsReadingWhenAsked() {
    #expect(AXHostSnapshot.read(shouldStop: { true }) == nil)
  }

  @Test func countsTheCPUAProcessUsedBetweenSnapshots() throws {
    let before = try #require(AXHostSnapshot.read())
    var value = 1.0
    let deadline = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) + 200_000_000
    while clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) < deadline {
      value = value.squareRoot() + 1
    }
    withExtendedLifetime(value) {}
    let after = try #require(AXHostSnapshot.read())

    let activity = AXHostActivity.between(
      before, after, requestStart: before.uptimeNanoseconds, ownUDID: nil, target: getpid(), cpuCount: 1,
      udid: { _ in nil })

    #expect(activity.userCPUMilliseconds >= 150, "this thread spun for 200 ms of its own CPU time")
  }

  @Test func readsTheArgumentsOfALiveProcess() {
    #expect(AXHostSnapshot.arguments(of: getpid()) == ProcessInfo.processInfo.arguments)
    #expect(AXHostSnapshot.arguments(of: -1) == nil)
  }

  @Test func findsTheDeviceInTheArgumentsOfItsLaunchdSim() {
    let plist = "data/var/run/launchd_bootstrap.plist"
    #expect(
      AXHostSnapshot.deviceUDID(fromArguments: [
        "launchd_sim", "/Users/me/Library/Developer/CoreSimulator/Devices/\(Self.udidA)/\(plist)",
      ]) == Self.udidA)
    #expect(
      AXHostSnapshot.deviceUDID(fromArguments: [
        "launchd_sim", "/tmp/sets/11111111-2222-4333-8444-555555555555/\(Self.udidA)/\(plist)",
      ]) == Self.udidA)
    #expect(AXHostSnapshot.deviceUDID(fromArguments: ["launchd_sim", "/var/run/launchd_bootstrap.plist"]) == nil)
  }

  @Test func readsEachSimulatorsDeviceOnceForTheLifeOfItsLaunchdSim() {
    let reads = OSAllocatedUnfairLock(initialState: 0)
    let arguments: (pid_t) -> [String]? = { _ in
      reads.withLock { $0 += 1 }
      return ["launchd_sim", "/Devices/\(Self.udidB)/data/var/run/launchd_bootstrap.plist"]
    }
    let launchd = AXHostProcess(pid: 88_001, ppid: 1, name: "launchd_sim", startMicroseconds: 42, cpuNanoseconds: 0)
    let restarted = AXHostProcess(pid: 88_001, ppid: 1, name: "launchd_sim", startMicroseconds: 43, cpuNanoseconds: 0)

    #expect(AXSimulatorDevices.udid(of: launchd, arguments: arguments) == Self.udidB)
    #expect(AXSimulatorDevices.udid(of: launchd, arguments: arguments) == Self.udidB)
    #expect(reads.withLock { $0 } == 1)
    #expect(AXSimulatorDevices.udid(of: restarted, arguments: arguments) == Self.udidB)
    #expect(reads.withLock { $0 } == 2, "a launchd_sim started again at the same pid is read again")
  }

  // MARK: - Activity between snapshots

  @Test func attributesEachProcesssCPUToItsSimulator() {
    let activity = Self.activity(ownUDID: Self.udidA)

    #expect(activity.simulators.map(\.launchdPID) == [100, 200, 400])
    #expect(activity.simulators.map(\.cpuMilliseconds) == [2950, 950, 0])
    #expect(activity.simulators.map(\.processes) == [4, 2, 1])
    #expect(activity.simulators.map(\.udid) == [Self.udidA, Self.udidB, nil])
    #expect(activity.outside.cpuMilliseconds == 410)
    #expect(activity.outside.processes == 3, "a process missed by the earlier snapshot is counted, its CPU is not")
    #expect(activity.userCPUMilliseconds == 4310)
  }

  @Test func marksTheRequestsOwnSimulatorByItsDevice() {
    let activity = Self.activity(ownUDID: Self.udidB, target: 0)

    #expect(activity.simulators.map(\.isOwn) == [false, true, false])
    #expect(activity.ownSimulatorCPUMilliseconds == 950)
    #expect(activity.otherSimulatorsCPUMilliseconds == 2950)
  }

  @Test func findsTheOwnSimulatorFromTheTargetWithoutADevice() {
    let activity = Self.activity(ownUDID: nil, target: 201)

    #expect(activity.ownSimulatorCPUMilliseconds == 950)
  }

  @Test func reportsNoNeighboursWhenTheOwnSimulatorIsUnknown() {
    let activity = Self.activity(ownUDID: nil, target: 0)

    #expect(activity.ownSimulatorCPUMilliseconds == nil)
    #expect(activity.otherSimulatorsCPUMilliseconds == nil)
    #expect(!activity.logFields.contains { $0.hasPrefix("other_sims_cpu_ms=") })
  }

  @Test func countsOnlySimulatorsThatUsedCPUAsActive() {
    let activity = Self.activity(ownUDID: Self.udidA)

    #expect(activity.simulators.count == 3)
    #expect(activity.activeSimulators == 2)
  }

  @Test func saysWhereTheWindowFallsInTheRequest() {
    let activity = Self.activity(ownUDID: Self.udidA)

    #expect(activity.startMilliseconds == 250)
    #expect(activity.windowMilliseconds == 2000)
    #expect(Self.activity(ownUDID: Self.udidA, requestStart: 10_500_000_000).startMilliseconds == -250)
  }

  @Test func measuresTheWholeHostFromItsTicks() {
    let activity = Self.activity(ownUDID: Self.udidA)

    #expect(activity.busyPercent == 92)
    #expect(activity.busyMilliseconds == 23833)
    #expect(Self.activity(ownUDID: Self.udidA, cpuCount: 0).busyMilliseconds == nil, "no CPU count, no busy time")
  }

  @Test func describesTheHostsProcessesInTheWindow() {
    let expected = [
      "host_window_start_ms=250 host_window_ms=2000 host_window_busy_ms=23833 host_window_busy_pct=92",
      "user_cpu_ms=4310 user_procs=10 sims=3 active_sims=2 own_sim_cpu_ms=2950 other_sims_cpu_ms=950",
      "sim_cpu=[*100/\(Self.udidA):2950/4(MobileSafari:2100,SpringBoard:500,helper:300);",
      "200/\(Self.udidB):950/2(Maps:900,launchd_sim:50); 400/-:0/1(); host:410/3(node:400,cyc:10)]",
      "host_top=[MobileSafari|102|100:2100; Maps|201|200:900; SpringBoard|101|100:500; node|300|1:400;",
      "helper|103|100:300; launchd_sim|100|1:50; launchd_sim|200|1:50; cyc|301|1:10]",
      "host_top_names=[MobileSafari#1:2100; Maps#1:900; SpringBoard#1:500; node#1:400; helper#1:300;",
      "launchd_sim#3:100; cyc#1:10]",
    ]
    #expect(Self.activity(ownUDID: Self.udidA).logFields.joined(separator: " ") == expected.joined(separator: " "))
  }

  // MARK: - Fixtures

  static let udidA = "0F3C2D1E-AAAA-4BBB-8CCC-123456789ABC"
  static let udidB = "1E2D3C4B-BBBB-4CCC-8DDD-23456789ABCD"

  /// Two busy simulators, one idle one, and processes outside them, from 250 ms into a request for 2 s.
  static func activity(
    ownUDID: String?, target: pid_t = 0, requestStart: UInt64 = 10_000_000_000, cpuCount: Int = 13
  ) -> AXHostActivity {
    let before = snapshot(
      [
        process(100, ppid: 1, "launchd_sim", started: 1000, milliseconds: 1000),
        process(101, ppid: 100, "SpringBoard", started: 1100, milliseconds: 3000),
        process(102, ppid: 100, "MobileSafari", started: 1200, milliseconds: 5000),
        process(200, ppid: 1, "launchd_sim", started: 2000, milliseconds: 800),
        process(201, ppid: 200, "Maps", started: 2100, milliseconds: 100),
        process(300, ppid: 1, "node", started: 3000, milliseconds: 10_000),
        process(400, ppid: 1, "launchd_sim", started: 4000, milliseconds: 50),
      ], uptimeNanoseconds: 10_250_000_000, wallMicroseconds: 5_000_000,
      ticks: AXHostCPUTicks(user: 1000, system: 500, idle: 8000, nice: 0))
    let after = snapshot(
      [
        process(100, ppid: 1, "launchd_sim", started: 1000, milliseconds: 1050),
        process(101, ppid: 100, "SpringBoard", started: 1100, milliseconds: 3500),
        process(102, ppid: 100, "MobileSafari", started: 1200, milliseconds: 7100),
        process(103, ppid: 100, "helper", started: 6_000_000, milliseconds: 300),
        process(200, ppid: 1, "launchd_sim", started: 2000, milliseconds: 850),
        process(201, ppid: 200, "Maps", started: 2100, milliseconds: 1000),
        process(300, ppid: 1, "node", started: 3000, milliseconds: 10_400),
        process(301, ppid: 1, "cyc", started: 6_500_000, milliseconds: 10),
        process(400, ppid: 1, "launchd_sim", started: 4000, milliseconds: 50),
        process(500, ppid: 1, "missed", started: 4500, milliseconds: 999),
      ], uptimeNanoseconds: 12_250_000_000, wallMicroseconds: 7_000_000,
      ticks: AXHostCPUTicks(user: 1900, system: 700, idle: 8100, nice: 0))
    return AXHostActivity.between(
      before, after, requestStart: requestStart, ownUDID: ownUDID, target: target, cpuCount: cpuCount,
      udid: { $0.pid == 100 ? udidA : $0.pid == 200 ? udidB : nil })
  }

  private static func process(
    _ pid: pid_t, ppid: pid_t, _ name: String, started: UInt64, milliseconds: UInt64
  ) -> AXHostProcess {
    AXHostProcess(pid: pid, ppid: ppid, name: name, startMicroseconds: started, cpuNanoseconds: milliseconds * 1_000_000)
  }

  private static func snapshot(
    _ processes: [AXHostProcess], uptimeNanoseconds: UInt64, wallMicroseconds: UInt64, ticks: AXHostCPUTicks?
  ) -> AXHostSnapshot {
    AXHostSnapshot(
      processes: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) }), ticks: ticks,
      uptimeNanoseconds: uptimeNanoseconds, wallMicroseconds: wallMicroseconds, readNanoseconds: 1_800_000)
  }
}
