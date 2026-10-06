/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import Foundation
import Testing
import os

private let start = Date(timeIntervalSince1970: 0)
private let timing = InstallProgressTiming.measure(stageStart: start, totalStart: start, now: start)

private func downloaded(_ bytes: Int64, of total: Int64?) -> InstallProgressEvent {
  .downloadProgress(timing: timing, bytesDownloaded: bytes, totalBytes: total)
}

private struct Refused: Error {}

@Suite struct InstallPercentagesTests {

  private func reported(_ events: [InstallProgressEvent]) async -> [Double] {
    let percentages = InstallPercentages()
    events.forEach(percentages.observe)
    percentages.finish()
    var reported: [Double] = []
    for await percent in percentages.percentages {
      reported.append(percent)
    }
    return reported
  }

  @Test func aDownloadOfKnownLengthReportsWholePercentages() {
    #expect(InstallPercentages.percent(of: downloaded(0, of: 200)) == 0)
    #expect(InstallPercentages.percent(of: downloaded(199, of: 200)) == 99)
    #expect(InstallPercentages.percent(of: downloaded(200, of: 200)) == 100)
    #expect(InstallPercentages.percent(of: downloaded(300, of: 200)) == 100)
  }

  @Test func aDownloadOfUnknownLengthAndEveryOtherStageReportNothing() {
    #expect(InstallPercentages.percent(of: downloaded(10, of: nil)) == nil)
    #expect(InstallPercentages.percent(of: downloaded(10, of: 0)) == nil)
    #expect(InstallPercentages.percent(of: .downloadCompleted(timing: timing, totalBytes: 10)) == nil)
    #expect(InstallPercentages.percent(of: .extractStarted(timing: timing, destinationPath: "/tmp")) == nil)
    #expect(InstallPercentages.percent(of: .installCompleted(timing: timing, artifactPath: "/tmp/A.app", name: "com.a")) == nil)
  }

  @Test func eachPercentageIsReportedOnceAsItRises() async {
    let events = [downloaded(0, of: 1000), downloaded(5, of: 1000), downloaded(10, of: 1000), downloaded(19, of: 1000), downloaded(500, of: 1000), downloaded(400, of: 1000), downloaded(1000, of: 1000)]
    #expect(await reported(events) == [1, 50, 100])
  }

  @Test func everyPercentageIsSentBeforeTheInstallReturns() async throws {
    let sent = OSAllocatedUnfairLock<[Double]>(initialState: [])
    let name = try await InstallPercentages.reporting(to: { percent in sent.withLock { $0.append(percent) } }) { onProgress in
      onProgress(downloaded(1, of: 4))
      onProgress(downloaded(4, of: 4))
      return "com.a"
    }
    #expect(name == "com.a")
    #expect(sent.withLock { $0 } == [25, 100])
  }

  @Test func aFailedInstallRethrowsAfterSendingWhatItReported() async {
    let sent = OSAllocatedUnfairLock<[Double]>(initialState: [])
    await #expect(throws: Refused.self) {
      try await InstallPercentages.reporting(to: { percent in sent.withLock { $0.append(percent) } }) { onProgress -> String in
        onProgress(downloaded(1, of: 2))
        throw Refused()
      }
    }
    #expect(sent.withLock { $0 } == [50])
  }
}
