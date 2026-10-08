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
    XCTAssertFalse(output.finishedConsuming.isOpen)

    process.terminate()
    try await application.waitForTermination()

    await waitForOutputToFinish()
    XCTAssertTrue(output.finishedConsuming.isOpen)
  }

  /// Fails the test, with `state()`, if `operation` is still running after `seconds`, rather than
  /// letting it run into the bundle's time allowance, which restarts the bundle and says nothing about
  /// what hung. An operation that overruns is left running.
  private func expectFinish(
    _ what: String,
    within seconds: TimeInterval = 15,
    state: @escaping @Sendable () -> String,
    _ operation: @escaping @Sendable () async throws -> Void
  ) async throws {
    let finished = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
      let once = ResumeOnce(continuation)
      Task {
        do {
          try await operation()
          once.resume(with: .success(true))
        } catch {
          once.resume(with: .failure(error))
        }
      }
      Task {
        try? await Task.sleep(for: .seconds(seconds))
        once.resume(with: .success(false))
      }
    }
    if !finished {
      XCTFail("\(what) did not finish within \(seconds) seconds: \(state())")
    }
  }

  private static func describe(_ application: SimulatorLaunchedApplication, _ process: Process) -> String {
    let signalable = kill(process.processIdentifier, 0) == 0 ? "signalable" : "gone (\(String(cString: strerror(errno))))"
    return "\(application); Process.isRunning \(process.isRunning); pid \(signalable)"
  }

  /// The output is finished after the termination, which lands on the simulator's work queue after
  /// the waiter has been woken.
  private func waitForOutputToFinish(timeout: TimeInterval = 5) async {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !output.finishedConsuming.isOpen && Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  func testTerminateKillsTheProcess() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)
    let state = { @Sendable in Self.describe(application, process) }

    try await expectFinish("terminate()", state: state) {
      try await application.terminate()
    }
    try await expectFinish("The process's exit", state: state) {
      await Task.detached { process.waitUntilExit() }.value
    }
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
    XCTAssertTrue(output.finishedConsuming.isOpen)
  }
}

/// Resumes a continuation with whichever result arrives first.
// SAFETY: `continuation` is only read and cleared while holding `lock`.
private final class ResumeOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Bool, Error>?

  init(_ continuation: CheckedContinuation<Bool, Error>) {
    self.continuation = continuation
  }

  func resume(with result: Result<Bool, Error>) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(with: result)
  }
}
