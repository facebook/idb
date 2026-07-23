/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Testing

/// Tests that `ReplReportParser` reconstructs a replayable session from a report built
/// by `ReplReportFormatter` — the formatter ⇄ parser round trip that replay relies on.
@Suite
struct ReplReportParserTests {

  private let epoch = Date(timeIntervalSince1970: 0)

  private func header(_ meta: SessionMeta) -> String {
    ReplReportFormatter.header(meta: meta, target: "iPhone 17.5", reason: nil, sessionID: "s", startedAt: epoch)
  }

  // MARK: - round trip

  @Test
  func parsesContextRunsAndSkipsCompileFailures() throws {
    let meta = SessionMeta(v: 1, context: "app", bundleID: "com.example.App", testBundlePath: nil, freshLaunch: true)
    var markdown = header(meta)
    markdown += ReplReportFormatter.runEntry(index: 0, code: "let a = 1", output: "Result:\n1", artifacts: [], at: Date(timeIntervalSince1970: 100))
    markdown += ReplReportFormatter.compileFailureEntry(index: 1, code: "let x =", compilerOutput: "error: expected expression", at: Date(timeIntervalSince1970: 150))
    markdown += ReplReportFormatter.runEntry(index: 2, code: "let b = 2", output: "Result:\n2", artifacts: [], at: Date(timeIntervalSince1970: 200))

    let parsed = try ReplReportParser.parse(markdown)

    #expect(parsed.context == .app(bundleID: "com.example.App", freshLaunch: true))
    #expect(parsed.skippedFailedRuns == 1)
    #expect(parsed.runs.count == 2)
    #expect(parsed.runs[0].index == 0)
    #expect(parsed.runs[0].code == "let a = 1")
    #expect(parsed.runs[0].timestamp == Date(timeIntervalSince1970: 100))
    #expect(parsed.runs[1].index == 2)
    #expect(parsed.runs[1].code == "let b = 2")
    #expect(parsed.runs[1].timestamp == Date(timeIntervalSince1970: 200))
  }

  @Test
  func parsesEachContextKind() throws {
    let simulator = try ReplReportParser.parse(
      header(
        SessionMeta(v: 1, context: "simulator", bundleID: nil, testBundlePath: nil, freshLaunch: nil)))
    #expect(simulator.context == .simulator)

    let test = try ReplReportParser.parse(
      header(
        SessionMeta(v: 1, context: "test", bundleID: nil, testBundlePath: "/tmp/Bundle.xctest", freshLaunch: nil)))
    #expect(test.context == .test(bundlePath: "/tmp/Bundle.xctest"))

    let appReattached = try ReplReportParser.parse(
      header(
        SessionMeta(v: 1, context: "app", bundleID: "com.example.App", testBundlePath: nil, freshLaunch: false)))
    #expect(appReattached.context == .app(bundleID: "com.example.App", freshLaunch: false))
  }

  @Test
  func runtimeExceptionRunIsReplayable() throws {
    var markdown = header(SessionMeta(v: 1, context: "simulator", bundleID: nil, testBundlePath: nil, freshLaunch: nil))
    markdown += ReplReportFormatter.runEntry(index: 0, code: "return try boom()", output: "Exception:\nBoom", artifacts: [], at: epoch)

    let parsed = try ReplReportParser.parse(markdown)
    #expect(parsed.runs.count == 1)
    #expect(parsed.runs[0].code == "return try boom()")
    #expect(parsed.skippedFailedRuns == 0)
  }

  // MARK: - fence robustness

  @Test
  func capturesCodeContainingFencesAndMarkerLikeLines() throws {
    // Code that itself contains a fence and lines that look like report structure must
    // be captured intact and never mistaken for a heading, marker, or a new run.
    let trickyCode = [
      "let s = \"\"\"",
      "```",
      "## Run 9 — 2020-01-01 00:00:00 +0000",
      "<!-- idb-repl-run: {\"index\":99,\"at\":0,\"status\":\"ok\"} -->",
      "\"\"\"",
    ].joined(separator: "\n")

    var markdown = header(SessionMeta(v: 1, context: "simulator", bundleID: nil, testBundlePath: nil, freshLaunch: nil))
    markdown += ReplReportFormatter.runEntry(index: 0, code: trickyCode, output: "Result:\nok", artifacts: [], at: epoch)

    let parsed = try ReplReportParser.parse(markdown)
    #expect(parsed.runs.count == 1)
    #expect(parsed.runs[0].code == trickyCode)
    #expect(parsed.runs[0].index == 0)
  }

  // MARK: - empty & malformed

  @Test
  func zeroRunsParsesToAnEmptyReplayableSession() throws {
    let parsed = try ReplReportParser.parse(
      header(
        SessionMeta(v: 1, context: "simulator", bundleID: nil, testBundlePath: nil, freshLaunch: nil)))
    #expect(parsed.runs.isEmpty)
    #expect(parsed.skippedFailedRuns == 0)
  }

  @Test
  func missingSessionMetaThrows() {
    let markdown = "# idb-repl session report\n\n## Run 0 — 2020-01-01 00:00:00 +0000\n\n```swift\nlet a = 1\n```\n"
    #expect(throws: ReplReportParseError.self) {
      try ReplReportParser.parse(markdown)
    }
  }

  @Test
  func unknownContextThrows() {
    let markdown =
      "<!-- idb-repl-session: s -->\n"
      + ReplReportFormatter.sessionMetaMarker(SessionMeta(v: 1, context: "bogus", bundleID: nil, testBundlePath: nil, freshLaunch: nil))
    #expect(throws: ReplReportParseError.self) {
      try ReplReportParser.parse(markdown)
    }
  }

  @Test
  func appContextWithoutBundleIDThrows() {
    let markdown =
      "<!-- idb-repl-session: s -->\n"
      + ReplReportFormatter.sessionMetaMarker(SessionMeta(v: 1, context: "app", bundleID: nil, testBundlePath: nil, freshLaunch: true))
    #expect(throws: ReplReportParseError.self) {
      try ReplReportParser.parse(markdown)
    }
  }
}

/// Tests the pure timing math backing `replay --realtime`.
@Suite
struct ReplayTimingTests {

  @Test
  func offsetsAnchorAtZeroAndAreDeltasFromTheFirstRun() {
    let timestamps = [
      Date(timeIntervalSince1970: 1000),
      Date(timeIntervalSince1970: 1002.5),
      Date(timeIntervalSince1970: 1005),
    ]
    #expect(ReplayTiming.offsets(forTimestamps: timestamps) == [0, 2.5, 5])
  }

  @Test
  func offsetsAreClampedNonDecreasing() {
    // A clock that went backwards between runs never schedules a run before its
    // predecessor: the offset carries forward instead of going negative.
    let timestamps = [
      Date(timeIntervalSince1970: 1000),
      Date(timeIntervalSince1970: 1003),
      Date(timeIntervalSince1970: 1001),
    ]
    #expect(ReplayTiming.offsets(forTimestamps: timestamps) == [0, 3, 3])
  }

  @Test
  func offsetsOfNoTimestampsIsEmpty() {
    #expect(ReplayTiming.offsets(forTimestamps: []).isEmpty)
  }
}
