/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
import XCTestBootstrap

final class FBExceptionInfoTests: XCTestCase {

  // MARK: - Initializer Behavioral Contracts

  func testConvenienceInit_DefaultsFileToNilAndLineToZero() {
    let fromConvenience = FBExceptionInfo(message: "error")
    let fromFull = FBExceptionInfo(message: "error", file: "Test.m", line: 10)

    XCTAssertNil(fromConvenience.file, "Convenience init must default file to nil")
    XCTAssertEqual(fromConvenience.line, 0, "Convenience init must default line to 0")

    XCTAssertNotNil(fromFull.file, "Full init must preserve the provided file")
    XCTAssertGreaterThan(fromFull.line, 0, "Full init must preserve the provided line")
  }

  // MARK: - Description Formatting

  func testDescription_IncludesMessageFileAndLine() {
    let info = FBExceptionInfo(message: "assertion failed", file: "MyTest.m", line: 55)
    let desc = info.description

    XCTAssertTrue(desc.contains("assertion failed"), "Description must include the exception message")
    XCTAssertTrue(desc.contains("MyTest.m"), "Description must include the file path")
    XCTAssertTrue(desc.contains("55"), "Description must include the line number")
  }
}
