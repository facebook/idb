/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTestBootstrap

final class FBXCTestReporterDouble: NSObject, FBXCTestReporter {

  private var mutableStartedSuites: [String] = []
  private var mutableEndedSuites: [String] = []
  private var mutableStartedTestCases: [[String]] = []
  private var mutablePassedTests: [[String]] = []
  private var mutableFailedTests: [[String]] = []
  private var mutableExternalEvents: [[String: Any]] = []
  private(set) var printReportWasCalled = false

  var logDirectoryPath: String?

  // MARK: - Accessors

  var startedSuites: [String] {
    return mutableStartedSuites
  }

  var endedSuites: [String] {
    return mutableEndedSuites
  }

  var startedTests: [[String]] {
    return mutableStartedTestCases
  }

  var passedTests: [[String]] {
    return mutablePassedTests
  }

  var failedTests: [[String]] {
    return mutableFailedTests
  }

  func events(withName name: String) -> [[String: Any]] {
    return mutableExternalEvents.filter { event in
      (event["event"] as? String) == name
    }
  }

  // MARK: - FBXCTestReporter

  func testCaseDidStart(forTestClass testClass: String, method: String) {
    mutableStartedTestCases.append([testClass, method])
  }

  func printReport() throws {
    printReportWasCalled = true
  }

  func handleExternalEvent(_ line: String) {
    guard let data = line.data(using: .utf8),
      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return
    }
    mutableExternalEvents.append(event)
  }

  func didBeginExecutingTestPlan() {}

  func testSuite(_ testSuite: String, didStartAt startTime: String) {
    mutableStartedSuites.append(testSuite)
  }

  func finished(with summary: FBTestManagerResultSummary) {
    mutableEndedSuites.append(summary.testSuite)
  }

  func didFinishExecutingTestPlan() {}

  func testHadOutput(_ output: String) {}

  func processWaitingForDebugger(withProcessIdentifier pid: pid_t) {}

  func didRecordVideo(atPath videoRecordingPath: String) {}

  func didSaveOSLog(atPath osLogPath: String) {}

  func didCopiedTestArtifact(_ testArtifactFilename: String, toPath path: String) {}

  func processUnderTestDidExit() {}

  func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?) {
    let pairs = [testClass, method]
    switch status {
    case .passed:
      mutablePassedTests.append(pairs)
    case .failed:
      mutableFailedTests.append(pairs)
    case .unknown:
      break
    @unknown default:
      break
    }
  }

  func didCrashDuringTest(_ error: Error) {}

  func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [FBExceptionInfo]) {}
}
