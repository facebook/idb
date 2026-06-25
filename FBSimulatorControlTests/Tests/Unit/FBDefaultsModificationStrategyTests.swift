/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class FBDefaultsModificationStrategyTests: XCTestCase {

  func testReadReturnsTrimmedStdoutOnZeroExit() throws {
    let output = FBInSimulatorToolOutput(stdout: Data("value\n".utf8), stderr: Data(), exitCode: 0)
    let result = try FBDefaultsModificationStrategy.stdout(orThrowFrom: output, command: .read(domain: "d", key: "k"), logger: nil)
    XCTAssertEqual(result as String, "value")
  }

  func testReadToleratesMissingKeyNonZeroExit() throws {
    // defaults returns 1 for a missing key/domain; a benign optional read, not a failure.
    let output = FBInSimulatorToolOutput(stdout: Data(), stderr: Data("does not exist\n".utf8), exitCode: 1)
    let result = try FBDefaultsModificationStrategy.stdout(orThrowFrom: output, command: .read(domain: "d", key: "missing"), logger: nil)
    XCTAssertEqual(result as String, "")
  }

  func testDeleteToleratesMissingKeyNonZeroExit() throws {
    let output = FBInSimulatorToolOutput(stdout: Data(), stderr: Data("does not exist\n".utf8), exitCode: 1)
    let result = try FBDefaultsModificationStrategy.stdout(orThrowFrom: output, command: .delete(path: "p", key: "k"), logger: nil)
    XCTAssertEqual(result as String, "")
  }

  func testWriteThrowsOnNonZeroExit() {
    let output = FBInSimulatorToolOutput(stdout: Data(), stderr: Data("bad type\n".utf8), exitCode: 1)
    XCTAssertThrowsError(try FBDefaultsModificationStrategy.stdout(orThrowFrom: output, command: .write(domain: "d", key: "k", type: "string", value: "v"), logger: nil)) { error in
      XCTAssertTrue(String(describing: error).contains("exit code 1"), "got: \(String(describing: error))")
      XCTAssertTrue(String(describing: error).contains("bad type"), "got: \(String(describing: error))")
    }
  }

  func testImportThrowsOnNonZeroExit() {
    let output = FBInSimulatorToolOutput(stdout: Data(), stderr: Data("boom\n".utf8), exitCode: 1)
    XCTAssertThrowsError(try FBDefaultsModificationStrategy.stdout(orThrowFrom: output, command: .importPlist(domainOrPath: "d", file: "/tmp/x.plist"), logger: nil))
  }
}
