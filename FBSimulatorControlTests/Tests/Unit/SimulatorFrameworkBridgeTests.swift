/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

final class SimulatorFrameworkBridgeTests: XCTestCase {

  func testFailureDetailsPreserveBothStreams() {
    XCTAssertEqual(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data("stderr".utf8),
        stdout: Data("stdout".utf8)),
      "stderr\nstdout")
    XCTAssertEqual(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data(),
        stdout: Data("stdout".utf8)),
      "stdout")
    XCTAssertEqual(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data("stderr".utf8),
        stdout: Data()),
      "stderr")
    XCTAssertEqual(
      SimulatorFrameworkBridgeError.failureDetails(stderr: Data(), stdout: Data()),
      "no output")
  }
}
