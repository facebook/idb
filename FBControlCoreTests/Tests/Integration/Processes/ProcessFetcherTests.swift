/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class ProcessFetcherTests: XCTestCase {

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
    let fetcher = ProcessFetcher()
    XCTAssertTrue(try fetcher.isProcessRunning(task.processIdentifier))
  }

  func testIsProcessRunningDeadProcess() {
    let fetcher = ProcessFetcher()
    task.terminate()
    task.waitUntilExit()
    XCTAssertThrowsError(try fetcher.isProcessRunning(task.processIdentifier))
  }

  func testIsProcessRunningSuspendedProcess() throws {
    let fetcher = ProcessFetcher()
    task.suspend()
    XCTAssertFalse(try fetcher.isProcessRunning(task.processIdentifier))
  }

  func testIsProcessStoppedRunningProcess() throws {
    let fetcher = ProcessFetcher()
    XCTAssertFalse(try fetcher.isProcessStopped(task.processIdentifier))
  }

  func testIsProcessStoppedDeadProcess() {
    let fetcher = ProcessFetcher()
    task.terminate()
    task.waitUntilExit()
    XCTAssertThrowsError(try fetcher.isProcessStopped(task.processIdentifier))
  }

  func testIsProcessStoppedSuspendedProcess() throws {
    let fetcher = ProcessFetcher()
    task.suspend()
    XCTAssertTrue(try fetcher.isProcessStopped(task.processIdentifier))
  }

  func testIsDebuggerAttachedToDeadProcess() {
    let fetcher = ProcessFetcher()
    task.terminate()
    task.waitUntilExit()
    XCTAssertThrowsError(try fetcher.isDebuggerAttached(to: task.processIdentifier))
  }

  func testIsDebuggerAttachedToProcessNoDebugger() throws {
    let fetcher = ProcessFetcher()
    XCTAssertFalse(try fetcher.isDebuggerAttached(to: task.processIdentifier))
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
    let info = try XCTUnwrap(ProcessFetcher().processInfo(for: process.processIdentifier))
    XCTAssertEqual(info.processIdentifier, process.processIdentifier)
    XCTAssertEqual(info.launchPath, "/bin/sleep")
    XCTAssertEqual(info.arguments, ["/bin/sleep", "10"])
  }

  // No arguments beyond argv[0], so the walk from the launch path to argv crosses only padding.
  func testProcessInfoForAProcessWithNoArguments() throws {
    let process = try launch("/bin/cat", arguments: [])
    let info = try XCTUnwrap(ProcessFetcher().processInfo(for: process.processIdentifier))
    XCTAssertEqual(info.launchPath, "/bin/cat")
    XCTAssertEqual(info.arguments, ["/bin/cat"])
  }

  func testProcessInfoForAProcessThatHasExited() {
    task.terminate()
    task.waitUntilExit()
    XCTAssertNil(ProcessFetcher().processInfo(for: task.processIdentifier))
  }

  func testProcessesWithProcessNameFindsTheProcess() {
    let found = ProcessFetcher().processes(withProcessName: "sleep")
    XCTAssertTrue(found.contains { $0.processIdentifier == task.processIdentifier }, "\(found)")
  }

  func testProcessesWithProcessNameForAnUnknownName() {
    XCTAssertEqual(ProcessFetcher().processes(withProcessName: "idb-no-such-process-\(getpid())"), [])
  }

  func testWaitForStopSignalResolvesOnceTheProcessIsStopped() async throws {
    task.suspend()
    try await ProcessFetcher.waitForStopSignal(process: task.processIdentifier)
  }
}
