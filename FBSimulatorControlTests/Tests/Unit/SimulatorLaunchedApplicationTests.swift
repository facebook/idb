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

/// Records that the launched application detached from its IO, without needing real files behind it.
///
/// `@unchecked Sendable`: `detachCount` is guarded by `lock`.
private final class AttachmentDouble: FBProcessFileAttachment, @unchecked Sendable {
  private let lock = NSLock()
  private var detaches = 0

  var detachCount: Int {
    lock.withLock { detaches }
  }

  override func detach() -> FBFuture<NSNull> {
    lock.withLock { detaches += 1 }
    return FBFuture<NSNull>.empty()
  }
}

final class SimulatorLaunchedApplicationTests: XCTestCase {

  private var simulator: Simulator!
  private var attachment: AttachmentDouble!
  private var spawned: [Process] = []

  override func setUp() {
    super.setUp()
    simulator = SimulatorTestSupport.testableSimulator()
    attachment = AttachmentDouble()
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
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: nil, stdErr: nil),
      launchMode: .failIfRunning)
    return try await bridgeFBFuture(
      SimulatorLaunchedApplication.application(
        withSimulator: simulator,
        configuration: configuration,
        attachment: attachment,
        launchFuture: FBFuture(result: NSNumber(value: process.processIdentifier))))
  }

  // MARK: - Tests

  func testWaitForTerminationResolvesOnceTheProcessExits() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)
    XCTAssertEqual(application.processIdentifier, process.processIdentifier)

    process.terminate()

    try await application.waitForTermination()
  }

  func testDetachesTheAttachmentOnceTheProcessExits() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)
    XCTAssertEqual(attachment.detachCount, 0)

    process.terminate()
    try await application.waitForTermination()

    await waitForDetach()
    XCTAssertEqual(attachment.detachCount, 1)
  }

  /// The detach is hung off the termination, which lands on the simulator's work queue after
  /// the waiter has been woken.
  private func waitForDetach(timeout: TimeInterval = 5) async {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while attachment.detachCount == 0 && Date() < deadline {
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

  func testTerminateDetachesTheAttachment() async throws {
    let process = try spawnBlockedProcess()
    let application = try await launchedApplication(forProcess: process)

    try await application.terminate()

    await waitForDetach()
    XCTAssertEqual(attachment.detachCount, 1)
  }
}
