/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class FBSimulatorLaunchCtlCommandsTests: XCTestCase {

  func testListReturnsStdoutOnZeroExit() throws {
    let output = FBInSimulatorToolOutput(stdout: Data("- 0 com.apple.foo\n".utf8), stderr: Data(), exitCode: 0)
    let result = try FBSimulatorLaunchCtlCommands.stdout(orThrowFrom: output, command: .list, logger: nil)
    XCTAssertEqual(result, "- 0 com.apple.foo\n")
  }

  func testListThrowsOnNonZeroExit() {
    let output = FBInSimulatorToolOutput(stdout: Data(), stderr: Data("boom\n".utf8), exitCode: 1)
    XCTAssertThrowsError(try FBSimulatorLaunchCtlCommands.stdout(orThrowFrom: output, command: .list, logger: nil)) { error in
      XCTAssertTrue(String(describing: error).contains("exit code 1"), "got: \(String(describing: error))")
    }
  }

  func testStopToleratesNotRunningExitCode() throws {
    // launchctl returns ESRCH (3) when the service is not running; idempotent, not a failure.
    let output = FBInSimulatorToolOutput(stdout: Data(), stderr: Data(), exitCode: 3)
    let result = try FBSimulatorLaunchCtlCommands.stdout(orThrowFrom: output, command: .stop(serviceName: "com.apple.foo"), logger: nil)
    XCTAssertEqual(result, "")
  }

  func testStopThrowsOnGenuineFailure() {
    // Any non-zero other than ESRCH is a genuine failure to stop a running service.
    let output = FBInSimulatorToolOutput(stdout: Data(), stderr: Data("Operation not permitted\n".utf8), exitCode: 1)
    XCTAssertThrowsError(try FBSimulatorLaunchCtlCommands.stdout(orThrowFrom: output, command: .stop(serviceName: "com.apple.foo"), logger: nil)) { error in
      XCTAssertTrue(String(describing: error).contains("Operation not permitted"), "got: \(String(describing: error))")
    }
  }

  func testStartThrowsOnNotRunningExitCode() {
    // Unlike stop, for start ESRCH (3) means there is no such service to start — a genuine failure.
    let output = FBInSimulatorToolOutput(stdout: Data(), stderr: Data("Could not find service\n".utf8), exitCode: 3)
    XCTAssertThrowsError(try FBSimulatorLaunchCtlCommands.stdout(orThrowFrom: output, command: .start(serviceName: "com.apple.foo"), logger: nil)) { error in
      XCTAssertTrue(String(describing: error).contains("exit code 3"), "got: \(String(describing: error))")
    }
  }

  // MARK: - serviceMap parsing

  // Mirrors `launchctl list`: a header row, a stopped service ("-" pid), a live service, and a
  // malformed line. Tab-separated like the real output (extractServiceName splits on whitespace).
  private static let listOutput = "PID\tStatus\tLabel\n-\t0\tcom.apple.stopped\n4321\t0\tcom.apple.SpringBoard\nnot a valid line\n"

  func testServiceMapParsesRunningStoppedAndSkipsNoise() {
    let map = FBSimulatorLaunchCtlCommands.serviceMap(fromListOutput: Self.listOutput)
    XCTAssertEqual(map["com.apple.SpringBoard"], 4321, "a live service maps to its pid")
    XCTAssertEqual(map["com.apple.stopped"], -1, "a loaded-but-stopped service maps to -1")
    XCTAssertNil(map["Label"], "the header row is skipped")
    XCTAssertNil(map["line"], "malformed (non-three-column) lines are skipped")
  }

  // MARK: - Liveness queries (default protocol implementations over listServices())

  func testServiceIsRunningReflectsLivePid() async throws {
    let launchCtl = FBSimulatorControlTests_LaunchCtl_Double.with(running: ["com.apple.SpringBoard": 4321], stopped: ["com.apple.idle"])
    let running = try await launchCtl.serviceIsRunning(named: "com.apple.SpringBoard")
    let stopped = try await launchCtl.serviceIsRunning(named: "com.apple.idle")
    let absent = try await launchCtl.serviceIsRunning(named: "com.apple.absent")
    XCTAssertTrue(running)
    XCTAssertFalse(stopped, "a loaded-but-stopped service is not running")
    XCTAssertFalse(absent, "an absent service is not running")
  }

  func testProcessIsRunningReflectsLivePid() async throws {
    let launchCtl = FBSimulatorControlTests_LaunchCtl_Double.with(running: ["com.apple.SpringBoard": 4321])
    let livePidRunning = try await launchCtl.processIsRunning(withProcessIdentifier: 4321)
    let absentPidRunning = try await launchCtl.processIsRunning(withProcessIdentifier: 9999)
    XCTAssertTrue(livePidRunning)
    XCTAssertFalse(absentPidRunning, "an unregistered pid is not running")
  }
}
