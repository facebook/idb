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
  func headerIncludesMarkerTitleContextAndTarget() {
    let header = ReplReportFormatter.header(
      context: "app (`com.example.App`)", target: "iPhone15,3 17.5", reason: "why", sessionID: "sess-1", startedAt: epoch)
    #expect(header.contains("<!-- idb-repl-session: sess-1 -->"))
    #expect(header.contains("# idb-repl session report"))
    #expect(header.contains("- **Context:** app (`com.example.App`)"))
    #expect(header.contains("- **Target:** iPhone15,3 17.5"))
    #expect(header.contains("- **Reason:** why"))
    #expect(header.contains("---"))
  }

  @Test
  func headerMarkerIsTheFirstLine() {
    let header = ReplReportFormatter.header(
      context: "simulator", target: "sim", reason: nil, sessionID: "abc", startedAt: epoch)
    #expect(header.hasPrefix("<!-- idb-repl-session: abc -->\n"))
  }

  @Test
  func headerOmitsReasonWhenAbsent() {
    let header = ReplReportFormatter.header(context: "simulator", target: "sim", reason: nil, sessionID: "s", startedAt: epoch)
    #expect(!header.contains("**Reason:**"))
  }

  @Test
  func headerOmitsReasonWhenEmpty() {
    let header = ReplReportFormatter.header(context: "simulator", target: "sim", reason: "", sessionID: "s", startedAt: epoch)
    #expect(!header.contains("**Reason:**"))
  }

  @Test
  func timestampsIncludeATimeZoneOffset() {
    let header = ReplReportFormatter.header(context: "simulator", target: "t", reason: nil, sessionID: "s", startedAt: epoch)
    let startedLine = header.split(separator: "\n").first { $0.contains("**Started:**") }.map(String.init) ?? ""
    #expect(startedLine.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}$"#, options: .regularExpression) != nil)
  }

  // MARK: - session marker round-trip

  @Test
  func sessionMarkerRoundTrips() {
    let id = "6F1C-abcd"
    let marker = ReplReportFormatter.sessionMarker(id)
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: marker) == id)
  }

  @Test
  func sessionIDParsesFromHeaderFirstLine() {
    let header = ReplReportFormatter.header(context: "simulator", target: "t", reason: nil, sessionID: "xyz", startedAt: epoch)
    let firstLine = header.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: firstLine) == "xyz")
  }

  @Test
  func nonMarkerLinesParseToNil() {
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: "# idb-repl session report") == nil)
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: "") == nil)
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: "<!-- something else -->") == nil)
  }

  // MARK: - reconnectMarker

  @Test
  func reconnectMarkerIsLabeled() {
    #expect(ReplReportFormatter.reconnectMarker(at: epoch).contains("Reconnected"))
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
  func compileFailureEntryIsLabeledFailedRunWithoutAnIndex() {
    let entry = ReplReportFormatter.compileFailureEntry(
      code: "let x =", compilerOutput: "error: expected expression", at: epoch)
    #expect(entry.contains("## Failed Run"))
    #expect(!entry.contains("## Run"))
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
