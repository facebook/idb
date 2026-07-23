/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import XCTest
import XCTestBootstrap

final class FBTestManagerTestReporterDouble: NSObject, FBXCTestReporter {

  var testCaseDidStartForTestClassCalled = false
  var testCaseDidFinishForTestClassCalled = false

  func processWaitingForDebugger(withProcessIdentifier pid: pid_t) {}
  func didBeginExecutingTestPlan() {}
  func didFinishExecutingTestPlan() {}
  func processUnderTestDidExit() {}
  func testSuite(_ testSuite: String, didStartAt startTime: String) {}

  func testCaseDidStart(forTestClass testClass: String, method: String) {
    testCaseDidStartForTestClassCalled = true
  }

  func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?) {
    testCaseDidFinishForTestClassCalled = true
  }

  func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [FBExceptionInfo]) {}
  func finished(with summary: FBTestManagerResultSummary) {}
  func testHadOutput(_ output: String) {}
  func handleExternalEvent(_ event: String) {}
  func printReport() throws {}
  func didCrashDuringTest(_ error: Error) {}
}

final class FBDeviceXCTestCommandsTests: XCTestCase {

  func testOverwriteXCTestRunPropertiesWithBaseProperties() {
    let baseProperties: [String: Any] = [
      "BundleIDBase": [
        "NoOverwrite": "Hello",
        "OverwriteMe": "Hi",
      ]
    ]

    let newProperties: [String: Any] = [
      "StubBundleId": [
        "OverwriteMe": "Hi overwrite!",
        "NoExist": "It's not defined in base so it won't be used.",
      ]
    ]

    let expectedProperties: [String: Any] = [
      "BundleIDBase": [
        "NoOverwrite": "Hello",
        "OverwriteMe": "Hi overwrite!",
      ]
    ]

    let realProperties = FBXcodeBuildOperation.overwriteXCTestRunProperties(withBaseProperties: baseProperties, newProperties: newProperties)

    XCTAssertEqual(realProperties as NSDictionary, expectedProperties as NSDictionary)
  }
}
