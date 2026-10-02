/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class SimulatorCrashLogCommandsTests: XCTestCase {

  private var directory: String!
  private var simulator: Simulator!
  private var commands: SimulatorCrashLogCommands!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("simulator_crash_logs_\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    simulator = SimulatorTestSupport.testableSimulator()
    commands = SimulatorCrashLogCommands(
      simulator: simulator,
      notifier: CrashLogNotifier.sharedInstance,
      store: CrashLogStore.store(forDirectories: [directory], logger: FBControlCoreLoggerFactory.logger(to: FBNullDataConsumer())))
  }

  override func tearDownWithError() throws {
    if let directory, FileManager.default.fileExists(atPath: directory) {
      try FileManager.default.removeItem(atPath: directory)
    }
    directory = nil
    simulator = nil
    commands = nil
    try super.tearDownWithError()
  }

  func testCrashesReadsReportsWrittenSinceTheLastRead() async throws {
    let before = try await commands.crashes(matching: NSPredicate(value: true), useCache: false)
    XCTAssertEqual(before.map(\.name), [])

    try writeReport(named: "ReplHost.crash", udid: simulator.udid)

    let after = try await commands.crashes(matching: NSPredicate(value: true), useCache: false)
    XCTAssertEqual(after.map(\.name), ["ReplHost.crash"])
  }

  func testPruneRemovesTheSimulatorsReports() async throws {
    let path = try writeReport(named: "ReplHost.crash", udid: simulator.udid)

    let pruned = try await commands.prune(matching: NSPredicate(value: true))

    XCTAssertEqual(pruned.map(\.name), ["ReplHost.crash"])
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }

  func testPruneLeavesOtherSimulatorsReports() async throws {
    let path = try writeReport(named: "Other.crash", udid: UUID().uuidString)
    let listed = try await commands.crashes(matching: NSPredicate(value: true), useCache: false)
    XCTAssertEqual(listed.map(\.name), ["Other.crash"])

    let pruned = try await commands.prune(matching: NSPredicate(value: true))

    XCTAssertEqual(pruned.map(\.name), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    let remaining = try await commands.crashes(matching: NSPredicate(value: true), useCache: false)
    XCTAssertEqual(remaining.map(\.name), ["Other.crash"])
  }

  func testPruneRemovesTheSimulatorsReportsWithARedactedPath() async throws {
    let path = try writeRedactedReport(named: "ReplHost-2026-09-30-102328.ips", udid: simulator.udid)
    let listed = try await commands.crashes(matching: NSPredicate(value: true), useCache: false)
    XCTAssertEqual(listed.map(\.name), ["ReplHost-2026-09-30-102328.ips"])

    let pruned = try await commands.prune(matching: NSPredicate(value: true))

    // BUG: the report names this simulator only in its coalition, which prune ignores — flipped in the following commit.
    XCTAssertEqual(pruned.map(\.name), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  func testPruneLeavesOtherSimulatorsReportsWithARedactedPath() async throws {
    let path = try writeRedactedReport(named: "Other-2026-09-30-102328.ips", udid: UUID().uuidString)
    let listed = try await commands.crashes(matching: NSPredicate(value: true), useCache: false)
    XCTAssertEqual(listed.map(\.name), ["Other-2026-09-30-102328.ips"])

    let pruned = try await commands.prune(matching: NSPredicate(value: true))

    XCTAssertEqual(pruned.map(\.name), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  @discardableResult
  private func writeReport(named name: String, udid: String) throws -> String {
    let path = (directory as NSString).appendingPathComponent(name)
    let report = """
      Process:               ReplHost [4242]
      Path:                  /Library/Developer/CoreSimulator/Devices/\(udid)/data/Containers/Bundle/Application/App/ReplHost.app/ReplHost
      Identifier:            com.facebook.idb.replhost
      Parent Process:        launchd_sim [4000]
      Date/Time:             2026-09-30 10:02:51.000 -0700
      """
    try report.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }

  /// A current macOS redacts the executable's path in a simulator app's `.ips` report, leaving the
  /// coalition as the only place the simulator's udid appears.
  @discardableResult
  private func writeRedactedReport(named name: String, udid: String) throws -> String {
    let path = (directory as NSString).appendingPathComponent(name)
    let report = """
      {"app_name":"ReplHost","bundleID":"com.facebook.idb.replhost","bug_type":"309","name":"ReplHost"}
      {
        "captureTime" : "2026-09-30 10:23:27.3628 -0700",
        "pid" : 45264,
        "procName" : "ReplHost",
        "procPath" : "\\/Volumes\\/VOLUME\\/*\\/ReplHost.app\\/ReplHost",
        "parentProc" : "launchd_sim",
        "parentPid" : 43138,
        "coalitionName" : "com.apple.CoreSimulator.SimDevice.\(udid)"
      }
      """
    try report.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }
}
