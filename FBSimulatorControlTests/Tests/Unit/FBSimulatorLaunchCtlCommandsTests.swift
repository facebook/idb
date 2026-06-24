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
}
