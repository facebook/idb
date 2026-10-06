/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

final class SimulatorLaunchedApplicationTests: XCTestCase {

  private var simulator: Simulator!
  private var output: ConsumableBuffer!
  private var spawned: [Process] = []

  override func setUp() {
    super.setUp()
    simulator = SimulatorTestSupport.testableSimulator()
    output = FBDataBuffer.consumableBuffer()
  }

  override func tearDown() {
    for process in spawned where process.isRunning {
      process.terminate()
    }
    spawned = []
    super.tearDown()
  }

  // MARK: - Helpers

  /// A process that blocks on a pipe it will never be written to, so it only exits when signalled.
  private func spawnBlockedProcess() throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/cat")
    process.standardInput = Pipe()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    spawned.append(process)
    return process
  }

  private func launchedApplication(forProcess process: Process) async throws -> SimulatorLaunchedApplication {
    let configuration = ApplicationLaunchConfiguration(
      bundleID: "com.facebook.test.launched",
      bundleName: nil,
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      launchMode: .failIfRunning)
    return SimulatorLaunchedApplication.application(
      withSimulator: simulator,
      configuration: configuration,
      outputs: [try FileBackedOutput.fifo(draining: output)],
      processIdentifier: process.processIdentifier)
  }

  // MARK: - Tests

  func testWaitForTerminationResolvesOnceTheProcessExits() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)
    XCTAssertEqual(application.processIdentifier, process.processIdentifier)

    process.terminate()

    try await application.waitForTermination()
  }

  func testFinishesTheOutputOnceTheProcessExits() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)
    XCTAssertFalse(output.finishedConsuming.hasCompleted)

    process.terminate()
    try await application.waitForTermination()

    await waitForOutputToFinish()
    XCTAssertTrue(output.finishedConsuming.hasCompleted)
  }

  /// The output is finished after the termination, which lands on the simulator's work queue after
  /// the waiter has been woken.
  private func waitForOutputToFinish(timeout: TimeInterval = 5) async {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !output.finishedConsuming.hasCompleted && Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  func testTerminateKillsTheProcess() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)

    try await application.terminate()

    process.waitUntilExit()
    XCTAssertFalse(process.isRunning)
  }

  func testWaitForTerminationIsCancelledByTerminate() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)

    try await application.terminate()

    do {
      try await application.waitForTermination()
      XCTFail("Expected the wait to report the explicit termination")
    } catch {
      XCTAssertTrue(error is CancellationError, "Expected a CancellationError, got \(error)")
    }
  }

  func testTerminateFinishesTheOutput() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)

    try await application.terminate()

    await waitForOutputToFinish()
    XCTAssertTrue(output.finishedConsuming.hasCompleted)
  }
}
