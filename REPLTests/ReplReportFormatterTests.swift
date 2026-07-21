/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Testing

/// Tests the pure Markdown formatting of session-report entries.
@Suite
struct ReplReportFormatterTests {

  private let epoch = Date(timeIntervalSince1970: 0)

  // MARK: - header

  @Test
  func headerIncludesTitleContextAndTarget() {
    let header = ReplReportFormatter.header(
      context: "app (`com.example.App`)", target: "iPhone15,3 17.5", reason: "why", startedAt: epoch)
    #expect(header.contains("# idb-repl session report"))
    #expect(header.contains("- **Context:** app (`com.example.App`)"))
    #expect(header.contains("- **Target:** iPhone15,3 17.5"))
    #expect(header.contains("- **Reason:** why"))
    #expect(header.contains("---"))
  }

  @Test
  func headerOmitsReasonWhenAbsent() {
    let header = ReplReportFormatter.header(context: "simulator", target: "sim", reason: nil, startedAt: epoch)
    #expect(!header.contains("**Reason:**"))
  }

  @Test
  func headerOmitsReasonWhenEmpty() {
    let header = ReplReportFormatter.header(context: "simulator", target: "sim", reason: "", startedAt: epoch)
    #expect(!header.contains("**Reason:**"))
  }

  // MARK: - runEntry

  @Test
  func runEntryContainsNumberedHeadingCodeAndOutput() {
    let entry = ReplReportFormatter.runEntry(index: 5, code: "return 1 + 1", output: "Result:\n2", at: epoch)
    #expect(entry.contains("## Run 5"))
    #expect(entry.contains("```swift\nreturn 1 + 1\n```"))
    #expect(entry.contains("**Output**"))
    #expect(entry.contains("Result:\n2"))
  }

  @Test
  func runEntryRecordsRuntimeException() {
    // A runtime exception is a completed run and is recorded like any other output.
    let entry = ReplReportFormatter.runEntry(index: 1, code: "return try boom()", output: "Exception:\nBoom", at: epoch)
    #expect(entry.contains("## Run 1"))
    #expect(entry.contains("Exception:\nBoom"))
    #expect(!entry.contains("compile failed"))
  }

  // MARK: - compileFailureEntry

  @Test
  func compileFailureEntryIsLabeled() {
    let entry = ReplReportFormatter.compileFailureEntry(
      index: 2, code: "let x =", compilerOutput: "error: expected expression", at: epoch)
    #expect(entry.contains("## Run 2"))
    #expect(entry.contains("(compile failed)"))
    #expect(entry.contains("**Compile error**"))
    #expect(entry.contains("error: expected expression"))
  }

  // MARK: - fencing

  @Test
  func codeContainingAFenceGetsALongerFence() {
    // Code that itself contains a ``` fence must not break out of its block: the
    // wrapping fence grows to four backticks.
    let entry = ReplReportFormatter.runEntry(index: 0, code: "let s = \"```\"", output: "Result:\nok", at: epoch)
    #expect(entry.contains("````swift"))
  }
}
