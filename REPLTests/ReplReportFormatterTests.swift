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

  private let appMeta = SessionMeta(v: 1, context: "app", bundleID: "com.example.App", testBundlePath: nil, freshLaunch: true)
  private let simulatorMeta = SessionMeta(v: 1, context: "simulator", bundleID: nil, testBundlePath: nil, freshLaunch: nil)

  // MARK: - header

  @Test
  func headerIncludesMarkerTitleContextAndTarget() {
    let header = ReplReportFormatter.header(
      meta: appMeta, target: "iPhone15,3 17.5", reason: "why", sessionID: "sess-1", startedAt: epoch)
    #expect(header.contains("<!-- idb-repl-session: sess-1 -->"))
    #expect(header.contains("# idb-repl session report"))
    #expect(header.contains("- **Context:** app (`com.example.App`)"))
    #expect(header.contains("- **Target:** iPhone15,3 17.5"))
    #expect(header.contains("- **Reason:** why"))
    #expect(header.contains("---"))
  }

  @Test
  func headerEmbedsTheSessionMetaMarker() {
    let header = ReplReportFormatter.header(
      meta: appMeta, target: "t", reason: nil, sessionID: "s", startedAt: epoch)
    let metaLine = header.split(separator: "\n").first { $0.contains("idb-repl-meta") }.map(String.init) ?? ""
    #expect(ReplReportFormatter.sessionMeta(fromLine: metaLine) == appMeta)
  }

  @Test
  func headerMarkerIsTheFirstLine() {
    let header = ReplReportFormatter.header(
      meta: simulatorMeta, target: "sim", reason: nil, sessionID: "abc", startedAt: epoch)
    #expect(header.hasPrefix("<!-- idb-repl-session: abc -->\n"))
  }

  @Test
  func headerOmitsReasonWhenAbsent() {
    let header = ReplReportFormatter.header(meta: simulatorMeta, target: "sim", reason: nil, sessionID: "s", startedAt: epoch)
    #expect(!header.contains("**Reason:**"))
  }

  @Test
  func headerOmitsReasonWhenEmpty() {
    let header = ReplReportFormatter.header(meta: simulatorMeta, target: "sim", reason: "", sessionID: "s", startedAt: epoch)
    #expect(!header.contains("**Reason:**"))
  }

  @Test
  func timestampsIncludeATimeZoneOffset() {
    let header = ReplReportFormatter.header(meta: simulatorMeta, target: "t", reason: nil, sessionID: "s", startedAt: epoch)
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
    let header = ReplReportFormatter.header(meta: simulatorMeta, target: "t", reason: nil, sessionID: "xyz", startedAt: epoch)
    let firstLine = header.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: firstLine) == "xyz")
  }

  @Test
  func nonMarkerLinesParseToNil() {
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: "# idb-repl session report") == nil)
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: "") == nil)
    #expect(ReplReportFormatter.sessionID(fromHeaderLine: "<!-- something else -->") == nil)
  }

  // MARK: - session meta marker round-trip

  @Test
  func sessionMetaMarkerRoundTripsForAllContexts() {
    let metas = [
      SessionMeta(v: 1, context: "simulator", bundleID: nil, testBundlePath: nil, freshLaunch: nil),
      SessionMeta(v: 1, context: "test", bundleID: nil, testBundlePath: "/tmp/Bundle.xctest", freshLaunch: nil),
      SessionMeta(v: 1, context: "app", bundleID: "com.example.App", testBundlePath: nil, freshLaunch: true),
      SessionMeta(v: 1, context: "app", bundleID: "com.example.App", testBundlePath: nil, freshLaunch: false),
    ]
    for meta in metas {
      let marker = ReplReportFormatter.sessionMetaMarker(meta)
      #expect(ReplReportFormatter.sessionMeta(fromLine: marker) == meta)
    }
  }

  @Test
  func sessionMetaParsesToNilForNonMetaLines() {
    #expect(ReplReportFormatter.sessionMeta(fromLine: "# idb-repl session report") == nil)
    #expect(ReplReportFormatter.sessionMeta(fromLine: "<!-- idb-repl-session: s -->") == nil)
  }

  // MARK: - reconnectMarker

  @Test
  func reconnectMarkerIsLabeled() {
    #expect(ReplReportFormatter.reconnectMarker(at: epoch).contains("Reconnected"))
  }

  // MARK: - runEntry

  @Test
  func runEntryContainsNumberedHeadingCodeAndOutput() {
    let entry = ReplReportFormatter.runEntry(index: 5, code: "return 1 + 1", output: "Result:\n2", artifacts: [], at: epoch)
    #expect(entry.contains("## Run 5"))
    #expect(entry.contains("```swift\nreturn 1 + 1\n```"))
    #expect(entry.contains("**Output**"))
    #expect(entry.contains("Result:\n2"))
  }

  @Test
  func runEntryEmbedsAnOKRunMarker() {
    let entry = ReplReportFormatter.runEntry(index: 5, code: "return 1 + 1", output: "Result:\n2", artifacts: [], at: epoch)
    let markerLine = entry.split(separator: "\n").first { $0.contains("idb-repl-run") }.map(String.init) ?? ""
    let meta = ReplReportFormatter.runMeta(fromLine: markerLine)
    #expect(meta?.index == 5)
    #expect(meta?.status == RunMeta.statusOK)
    #expect(meta?.at == epoch.timeIntervalSince1970)
  }

  @Test
  func runEntryRecordsRuntimeException() {
    // A runtime exception is a completed run and is recorded like any other output.
    let entry = ReplReportFormatter.runEntry(index: 1, code: "return try boom()", output: "Exception:\nBoom", artifacts: [], at: epoch)
    #expect(entry.contains("## Run 1"))
    #expect(entry.contains("Exception:\nBoom"))
    #expect(!entry.contains("compile failed"))
  }

  @Test
  func runEntryWithoutArtifactsHasNoArtifactsBlock() {
    let entry = ReplReportFormatter.runEntry(index: 0, code: "return 1", output: "Result:\n1", artifacts: [], at: epoch)
    #expect(!entry.contains("**Artifacts**"))
  }

  // MARK: - runEntry artifacts

  @Test
  func runEntryEmbedsImageArtifacts() {
    let entry = ReplReportFormatter.runEntry(
      index: 5, code: "IDB.screenshot.save()", output: "Result:\nok",
      artifacts: ["session/screenshot_5_1.png"], at: epoch)
    #expect(entry.contains("**Artifacts**"))
    #expect(entry.contains("![screenshot_5_1.png](session/screenshot_5_1.png)"))
  }

  @Test
  func runEntryLinksNonImageArtifacts() {
    let entry = ReplReportFormatter.runEntry(
      index: 5, code: "IDB.video.stopRecording()", output: "Result:\nok",
      artifacts: ["session/video_5_1.mp4"], at: epoch)
    // Video is linked, not embedded as an image.
    #expect(entry.contains("[video_5_1.mp4](session/video_5_1.mp4)"))
    #expect(!entry.contains("![video_5_1.mp4]"))
  }

  // MARK: - compileFailureEntry

  @Test
  func compileFailureEntryIsLabeledFailedRun() {
    let entry = ReplReportFormatter.compileFailureEntry(
      index: 3, code: "let x =", compilerOutput: "error: expected expression", at: epoch)
    #expect(entry.contains("## Failed Run"))
    #expect(!entry.contains("## Run"))
    #expect(entry.contains("**Compile error**"))
    #expect(entry.contains("error: expected expression"))
  }

  @Test
  func compileFailureEntryEmbedsACompileFailedRunMarker() {
    let entry = ReplReportFormatter.compileFailureEntry(
      index: 3, code: "let x =", compilerOutput: "error: expected expression", at: epoch)
    let markerLine = entry.split(separator: "\n").first { $0.contains("idb-repl-run") }.map(String.init) ?? ""
    let meta = ReplReportFormatter.runMeta(fromLine: markerLine)
    #expect(meta?.index == 3)
    #expect(meta?.status == RunMeta.statusCompileFailed)
  }

  // MARK: - fencing

  @Test
  func codeContainingAFenceGetsALongerFence() {
    // Code that itself contains a ``` fence must not break out of its block: the
    // wrapping fence grows to four backticks.
    let entry = ReplReportFormatter.runEntry(index: 0, code: "let s = \"```\"", output: "Result:\nok", artifacts: [], at: epoch)
    #expect(entry.contains("````swift"))
  }
}
