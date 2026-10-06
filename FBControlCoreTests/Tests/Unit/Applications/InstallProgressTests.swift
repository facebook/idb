/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest

final class InstallProgressTests: XCTestCase {

  // MARK: - Timing

  func testTiming_MeasuresStageAndTotalSeparately() {
    let totalStart = Date(timeIntervalSinceNow: -2.0)
    let stageStart = Date(timeIntervalSinceNow: -0.5)

    let event = InstallProgressEvent.installCompleted(
      timing: .measure(stageStart: stageStart, totalStart: totalStart),
      artifactPath: "/x",
      name: "com.x")

    XCTAssertEqual(event.stage, .install)
    XCTAssertEqual(event.phase, .completed)
    XCTAssertEqual(Double(event.elapsedMs), 500, accuracy: 100)
    XCTAssertEqual(Double(event.totalElapsedMs), 2000, accuracy: 100)
  }

  /// Extraction consumes the download's bytes as they arrive, so the two stages
  /// overlap and each has to time against its own start. Deriving one from the
  /// other by subtracting totals would report extraction as having taken as long
  /// as the download.
  func testTiming_WhenStagesOverlap_EachReportsItsOwnElapsed() {
    // The clock is passed in rather than slept through, because a real sleep
    // would make this flaky on a loaded host. The results are still not exact:
    // `Date` holds an interval near 7.8e8 as a `Double`, so adding 0.10 and
    // subtracting it again can land a hair under, and the conversion to
    // milliseconds truncates. Hence the tolerance rather than equality.
    let totalStart = Date()
    let downloadStart = totalStart
    let extractStart = totalStart.addingTimeInterval(0.05)
    let now = totalStart.addingTimeInterval(0.10)

    let downloadCompleted = InstallProgressEvent.downloadCompleted(
      timing: .measure(stageStart: downloadStart, totalStart: totalStart, now: now),
      totalBytes: 0)
    let extractCompleted = InstallProgressEvent.extractCompleted(
      timing: .measure(stageStart: extractStart, totalStart: totalStart, now: now),
      destinationPath: "/tmp/x")

    XCTAssertEqual(Double(downloadCompleted.elapsedMs), 100, accuracy: 1)
    XCTAssertEqual(Double(extractCompleted.elapsedMs), 50, accuracy: 1)
    XCTAssertLessThan(
      extractCompleted.elapsedMs, downloadCompleted.elapsedMs,
      "The later stage reports less elapsed time despite the same total")
    XCTAssertEqual(downloadCompleted.totalElapsedMs, extractCompleted.totalElapsedMs)
  }

  // MARK: - Stage and phase

  func testEvent_ReportsItsStageAndPhase() {
    let timing = InstallProgressTiming(elapsedMs: 0, totalElapsedMs: 0)
    // swiftlint:disable:next force_unwrapping
    // patternlint-disable-next-line use-meta-url-wrapper-for-url
    let url = URL(string: "https://example.invalid/app.ipa")!

    let cases: [(InstallProgressEvent, InstallStage, InstallPhase)] = [
      (.downloadStarted(timing: timing, url: url), .download, .started),
      (.downloadProgress(timing: timing, bytesDownloaded: 1, totalBytes: nil), .download, .progress),
      (.downloadCompleted(timing: timing, totalBytes: 1), .download, .completed),
      (.extractStarted(timing: timing, destinationPath: "/x"), .extract, .started),
      (.extractCompleted(timing: timing, destinationPath: "/x"), .extract, .completed),
      (.installStarted(timing: timing, artifactPath: "/x"), .install, .started),
      (.installCompleted(timing: timing, artifactPath: "/x", name: "com.x"), .install, .completed),
    ]

    for (event, stage, phase) in cases {
      XCTAssertEqual(event.stage, stage)
      XCTAssertEqual(event.phase, phase)
    }
  }

  // MARK: - Download progress throttling

  func testProgressState_ReportsOnceTheByteThresholdIsCrossed() throws {
    var progress = DownloadProgressState(startedAt: Date())

    XCTAssertNil(
      progress.track(
        byteCount: 3_000_000, byteThreshold: 5_000_000, timeThreshold: 999.0),
      "Below the threshold, nothing is reported")

    let update = try XCTUnwrap(
      progress.track(
        byteCount: 3_000_000, byteThreshold: 5_000_000, timeThreshold: 999.0))
    XCTAssertEqual(update.bytesDownloaded, 6_000_000)
    XCTAssertNil(update.totalBytes)
    XCTAssertEqual(progress.downloadedBytes, 6_000_000)

    XCTAssertNil(
      progress.track(
        byteCount: 1_000_000, byteThreshold: 5_000_000, timeThreshold: 999.0),
      "The threshold is measured from the last report, not from zero")
    XCTAssertEqual(
      progress.downloadedBytes, 7_000_000, "Unreported bytes still accumulate")
  }

  /// A slow transfer should still look alive, so time alone is enough to report.
  func testProgressState_ReportsOnceTheTimeThresholdIsCrossed() throws {
    var progress = DownloadProgressState(startedAt: Date(timeIntervalSinceNow: -10))

    let update = try XCTUnwrap(
      progress.track(byteCount: 1, byteThreshold: .max, timeThreshold: 1.0))
    XCTAssertEqual(update.bytesDownloaded, 1)
  }

  func testProgressState_IncludesTheContentLengthOnceKnown() throws {
    var progress = DownloadProgressState(startedAt: Date())
    progress.observe(expectedContentLength: 50_000_000)

    let update = try XCTUnwrap(
      progress.track(byteCount: 10_000_000, byteThreshold: 1, timeThreshold: 999.0))
    XCTAssertEqual(update.bytesDownloaded, 10_000_000)
    XCTAssertEqual(update.totalBytes, 50_000_000)
  }

  /// A server that does not say how much to expect reports zero or a negative
  /// length, which is not a total.
  func testProgressState_TreatsAnUnknownContentLengthAsUnknown() {
    var progress = DownloadProgressState(startedAt: Date())

    progress.observe(expectedContentLength: -1)
    XCTAssertNil(progress.totalBytes)
    progress.observe(expectedContentLength: 0)
    XCTAssertNil(progress.totalBytes)
    progress.observe(expectedContentLength: 1234)
    XCTAssertEqual(progress.totalBytes, 1234)
  }
}
