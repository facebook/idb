/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol XCTestReporter: AnyObject {

  func processWaitingForDebugger(withProcessIdentifier pid: pid_t)

  func didBeginExecutingTestPlan()

  func didFinishExecutingTestPlan()

  func processUnderTestDidExit()

  func testSuite(_ testSuite: String, didStartAt startTime: String)

  func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?)

  func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [TestExceptionInfo])

  func testCaseDidStart(forTestClass testClass: String, method: String)

  func finished(with summary: TestManagerResultSummary)

  func testHadOutput(_ output: String)

  func handleExternalEvent(_ event: String)

  func printReport() throws

  func didCrashDuringTest(_ error: Error)

  func testCase(_ testClass: String, method: String, willStartActivity activity: FBActivityRecord)

  func testCase(_ testClass: String, method: String, didFinishActivity activity: FBActivityRecord)

  func testPlanDidFail(withMessage message: String)
}

extension XCTestReporter {
  public func testCase(_ testClass: String, method: String, willStartActivity activity: FBActivityRecord) {}

  public func testCase(_ testClass: String, method: String, didFinishActivity activity: FBActivityRecord) {}

  public func testPlanDidFail(withMessage message: String) {}
}
