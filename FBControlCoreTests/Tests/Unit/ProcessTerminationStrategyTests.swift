/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import XCTest

/// Reports every process as absent, so the existence check fails before any signal is sent.
private final class AbsentProcessFetcher: ProcessFetcher {
  override func processInfo(for processIdentifier: pid_t) -> RunningProcessInfo? {
    nil
  }
}

final class ProcessTerminationStrategyTests: XCTestCase {

  /// Beyond the default `kern.maxproc`, so no process can ever hold it and `kill` fails with ESRCH.
  private let unallocatablePID: pid_t = 999_999

  private var logger: ControlCoreLoggerDouble!
  private var spawned: [Process] = []

  override func setUp() {
    super.setUp()
    logger = ControlCoreLoggerDouble()
  }

  override func tearDown() {
    for process in spawned where process.isRunning {
      process.terminate()
    }
    spawned = []
    super.tearDown()
  }

  // MARK: - Helpers

  /// A process that blocks on a pipe it will never be written to, so it only leaves the process
  /// table when signalled.
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

  private func strategy(
    signo: Int32 = SIGKILL,
    options: ProcessTerminationStrategyOptions,
    processFetcher: ProcessFetcher = ProcessFetcher()
  ) -> ProcessTerminationStrategy {
    ProcessTerminationStrategy.strategy(
      withConfiguration: ProcessTerminationStrategyConfiguration(signo: signo, options: options),
      processFetcher: processFetcher,
      workQueue: DispatchQueue(label: "com.facebook.fbcontrolcore.termination_strategy_tests"),
      logger: logger)
  }

  private func terminationError(_ error: Error) -> ProcessTerminationStrategyError? {
    error as? ProcessTerminationStrategyError
  }

  // MARK: - Tests

  func testFailsWithoutSignallingWhenTheProcessIsNotFound() async throws {
    let process = try spawnBlockedProcess()
    let strategy = strategy(options: [.checkProcessExistsBeforeSignal], processFetcher: AbsentProcessFetcher())

    do {
      try await bridgeFBFutureVoid(strategy.killProcessIdentifier(process.processIdentifier))
      XCTFail("Expected the kill to fail for a process the fetcher does not report")
    } catch {
      guard case .processDoesNotExist(let processIdentifier)? = terminationError(error) else {
        return XCTFail("Unexpected error \(error)")
      }
      XCTAssertEqual(processIdentifier, process.processIdentifier)
    }

    XCTAssertTrue(process.isRunning)
  }

  func testFailsWhenTheSignalCannotBeDelivered() async throws {
    let strategy = strategy(options: [])

    do {
      try await bridgeFBFutureVoid(strategy.killProcessIdentifier(unallocatablePID))
      XCTFail("Expected the kill of an unallocatable process identifier to fail")
    } catch {
      guard case .killFailed(let processIdentifier, _)? = terminationError(error) else {
        return XCTFail("Unexpected error \(error)")
      }
      XCTAssertEqual(processIdentifier, unallocatablePID)
    }
  }

  func testSignalsWithoutWaitingWhenDeathIsNotChecked() async throws {
    let process = try spawnBlockedProcess()
    let strategy = strategy(options: [])

    try await bridgeFBFutureVoid(strategy.killProcessIdentifier(process.processIdentifier))

    process.waitUntilExit()
    XCTAssertEqual(process.terminationReason, .uncaughtSignal)
  }

  func testResolvesOnceTheProcessLeavesTheProcessTable() async throws {
    let process = try spawnBlockedProcess()
    let strategy = strategy(options: [.checkProcessExistsBeforeSignal, .checkDeathAfterSignal])
    // The signalled child is a zombie — and so still in the process table — until it is reaped.
    DispatchQueue.global().async {
      process.waitUntilExit()
    }

    try await bridgeFBFutureVoid(strategy.killProcessIdentifier(process.processIdentifier))

    XCTAssertNil(ProcessFetcher().processInfo(for: process.processIdentifier))
  }
}
