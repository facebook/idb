/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The reporting surface the Objective-C DTX layer sees, so `XCTestReporter` need not be `@objc`.
@objc public protocol TestManagerReportSink: NSObjectProtocol {
  @objc(testSuite:didStartAt:)
  func testSuite(_ testSuite: String, didStartAt startTime: String)

  func didBeginExecutingTestPlan()

  func didFinishExecutingTestPlan()

  @objc(testCaseDidStartForTestClass:method:)
  func testCaseDidStart(forTestClass testClass: String, method: String)

  @objc(testCaseDidFailForTestClass:method:exceptions:)
  func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [TestExceptionInfo])

  @objc(testCaseDidFinishForTestClass:method:withStatus:duration:logs:)
  func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?)

  @objc(finishedWithSummary:)
  func finished(with summary: TestManagerResultSummary)

  @objc(testCase:method:willStartActivity:)
  func testCase(_ testClass: String, method: String, willStartActivity activity: FBActivityRecord)

  @objc(testCase:method:didFinishActivity:)
  func testCase(_ testClass: String, method: String, didFinishActivity activity: FBActivityRecord)
}

final class XCTestReporterSink: NSObject, TestManagerReportSink {
  private let reporter: XCTestReporter

  init(_ reporter: XCTestReporter) {
    self.reporter = reporter
  }

  func testSuite(_ testSuite: String, didStartAt startTime: String) {
    reporter.testSuite(testSuite, didStartAt: startTime)
  }

  func didBeginExecutingTestPlan() {
    reporter.didBeginExecutingTestPlan()
  }

  func didFinishExecutingTestPlan() {
    reporter.didFinishExecutingTestPlan()
  }

  func testCaseDidStart(forTestClass testClass: String, method: String) {
    reporter.testCaseDidStart(forTestClass: testClass, method: method)
  }

  func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [TestExceptionInfo]) {
    reporter.testCaseDidFail(forTestClass: testClass, method: method, exceptions: exceptions)
  }

  func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?) {
    reporter.testCaseDidFinish(forTestClass: testClass, method: method, with: status, duration: duration, logs: logs)
  }

  func finished(with summary: TestManagerResultSummary) {
    reporter.finished(with: summary)
  }

  func testCase(_ testClass: String, method: String, willStartActivity activity: FBActivityRecord) {
    reporter.testCase(testClass, method: method, willStartActivity: activity)
  }

  func testCase(_ testClass: String, method: String, didFinishActivity activity: FBActivityRecord) {
    reporter.testCase(testClass, method: method, didFinishActivity: activity)
  }
}
