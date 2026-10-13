/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBXCTestCore
import Foundation
import Testing

@Suite
struct TestExceptionInfoTests {

  // MARK: - Initializer Behavioral Contracts

  @Test
  func convenienceInit_DefaultsFileToNilAndLineToZero() {
    let fromConvenience = TestExceptionInfo(message: "error")
    let fromFull = TestExceptionInfo(message: "error", file: "Test.m", line: 10)

    #expect(fromConvenience.file == nil, "Convenience init must default file to nil")
    #expect(fromConvenience.line == 0, "Convenience init must default line to 0")

    #expect(fromFull.file != nil, "Full init must preserve the provided file")
    #expect(fromFull.line > 0, "Full init must preserve the provided line")
  }

  // MARK: - Description Formatting

  @Test
  func description_IncludesMessageFileAndLine() {
    let info = TestExceptionInfo(message: "assertion failed", file: "MyTest.m", line: 55)
    let desc = info.description

    #expect(desc.contains("assertion failed"), "Description must include the exception message")
    #expect(desc.contains("MyTest.m"), "Description must include the file path")
    #expect(desc.contains("55"), "Description must include the line number")
  }
}
