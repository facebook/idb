/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBXCTestReporter: NSObjectProtocol {

  @objc(processWaitingForDebuggerWithProcessIdentifier:)
  func processWaitingForDebugger(withProcessIdentifier pid: pid_t)

  @objc func didBeginExecutingTestPlan()

  @objc func didFinishExecutingTestPlan()

  @objc func processUnderTestDidExit()

  @objc(testSuite:didStartAt:)
  func testSuite(_ testSuite: String, didStartAt startTime: String)

  @objc(testCaseDidFinishForTestClass:method:withStatus:duration:logs:)
  func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?)

  @objc(testCaseDidFailForTestClass:method:exceptions:)
  func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [FBExceptionInfo])

  @objc(testCaseDidStartForTestClass:method:)
  func testCaseDidStart(forTestClass testClass: String, method: String)

  @objc(finishedWithSummary:)
  func finished(with summary: FBTestManagerResultSummary)

  @objc(testHadOutput:)
  func testHadOutput(_ output: String)

  @objc(handleExternalEvent:)
  func handleExternalEvent(_ event: String)

  @objc(printReportWithError:)
  func printReport() throws

  @objc(didCrashDuringTest:)
  func didCrashDuringTest(_ error: Error)

  // MARK: Optional

  @objc(testCase:method:willStartActivity:)
  optional func testCase(_ testClass: String, method: String, willStartActivity activity: FBActivityRecord)

  @objc(testCase:method:didFinishActivity:)
  optional func testCase(_ testClass: String, method: String, didFinishActivity activity: FBActivityRecord)

  @objc(testPlanDidFailWithMessage:)
  optional func testPlanDidFail(withMessage message: String)

  @objc(didRecordVideoAtPath:)
  optional func didRecordVideo(atPath videoRecordingPath: String)

  @objc(didSaveOSLogAtPath:)
  optional func didSaveOSLog(atPath osLogPath: String)

  @objc(didCopiedTestArtifact:toPath:)
  optional func didCopiedTestArtifact(_ testArtifactFilename: String, toPath path: String)
}
