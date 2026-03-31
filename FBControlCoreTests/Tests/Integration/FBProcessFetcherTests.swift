/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

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
}
