/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBProcessFetcherTests: XCTestCase {

  private var task: Process!

  override func setUp() {
    super.setUp()
    let process = Process()
    process.launchPath = "/bin/sleep"
    process.arguments = ["10"]
    task = process
    task.launch()
  }

  override func tearDown() {
    if task.isRunning {
      task.terminate()
      task.waitUntilExit()
    }
    task = nil
    super.tearDown()
  }

  func testIsProcessRunningRunningProcess() throws {
    let fetcher = FBProcessFetcher()
    try fetcher.isProcessRunning(task.processIdentifier)
  }

  func testIsProcessRunningDeadProcess() {
    let fetcher = FBProcessFetcher()
    task.terminate()
    task.waitUntilExit()
    XCTAssertThrowsError(try fetcher.isProcessRunning(task.processIdentifier))
  }

  func testIsProcessRunningSuspendedProcess() {
    let fetcher = FBProcessFetcher()
    task.suspend()
    XCTAssertThrowsError(try fetcher.isProcessRunning(task.processIdentifier))
  }

  func testIsProcessStoppedRunningProcess() {
    let fetcher = FBProcessFetcher()
    XCTAssertThrowsError(try fetcher.isProcessStopped(task.processIdentifier))
  }

  func testIsProcessStoppedDeadProcess() {
    let fetcher = FBProcessFetcher()
    task.terminate()
    task.waitUntilExit()
    XCTAssertThrowsError(try fetcher.isProcessStopped(task.processIdentifier))
  }

  func testIsProcessStoppedSuspendedProcess() throws {
    let fetcher = FBProcessFetcher()
    task.suspend()
    try fetcher.isProcessStopped(task.processIdentifier)
  }

  func testIsDebuggerAttachedToDeadProcess() {
    let fetcher = FBProcessFetcher()
    task.terminate()
    task.waitUntilExit()
    XCTAssertThrowsError(try fetcher.isDebuggerAttached(to: task.processIdentifier))
  }

  func testIsDebuggerAttachedToProcessNoDebugger() {
    let fetcher = FBProcessFetcher()
    XCTAssertThrowsError(try fetcher.isDebuggerAttached(to: task.processIdentifier))
  }

  // MARK: - Process table queries

  /// Launches `path`, holding stdin open so a process that reads it stays alive for the test.
  /// The environment is not asserted anywhere: the OS no longer reports another process's
  /// environment through `KERN_PROCARGS2`, so the fetcher reads it back empty.
  private func launch(_ path: String, arguments: [String]) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardInput = Pipe()
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    addTeardownBlock {
      if process.isRunning {
        process.terminate()
        process.waitUntilExit()
      }
    }
    return process
  }

  func testProcessInfoReadsTheLaunchPathAndArguments() throws {
    let process = try launch("/bin/sleep", arguments: ["10"])
    let info = try XCTUnwrap(FBProcessFetcher().processInfo(for: process.processIdentifier))
    XCTAssertEqual(info.processIdentifier, process.processIdentifier)
    XCTAssertEqual(info.launchPath, "/bin/sleep")
    XCTAssertEqual(info.arguments, ["/bin/sleep", "10"])
  }

  // No arguments beyond argv[0], so the walk from the launch path to argv crosses only padding.
  func testProcessInfoForAProcessWithNoArguments() throws {
    let process = try launch("/bin/cat", arguments: [])
    let info = try XCTUnwrap(FBProcessFetcher().processInfo(for: process.processIdentifier))
    XCTAssertEqual(info.launchPath, "/bin/cat")
    XCTAssertEqual(info.arguments, ["/bin/cat"])
  }

  func testProcessInfoForAProcessThatHasExited() {
    task.terminate()
    task.waitUntilExit()
    XCTAssertNil(FBProcessFetcher().processInfo(for: task.processIdentifier))
  }

  func testProcessesWithProcessNameFindsTheProcess() {
    let found = FBProcessFetcher().processes(withProcessName: "sleep")
    XCTAssertTrue(found.contains { $0.processIdentifier == task.processIdentifier }, "\(found)")
  }

  func testProcessesWithProcessNameForAnUnknownName() {
    XCTAssertEqual(FBProcessFetcher().processes(withProcessName: "idb-no-such-process-\(getpid())"), [])
  }

  func testWaitStopSignalResolvesOnceTheProcessIsStopped() async throws {
    let waiting = FBProcessFetcher.waitStopSignal(forProcess: task.processIdentifier)
    task.suspend()
    try await bridgeFBFutureVoid(waiting)
  }
}
