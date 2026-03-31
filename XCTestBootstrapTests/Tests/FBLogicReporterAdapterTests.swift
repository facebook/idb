/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
import XCTestBootstrap

private func beginTestSuiteDict() -> [String: Any] {
  return [
    "event": "begin-test-suite",
    "suite": "NARANJA",
    "timestamp": "1970",
  ]
}

private func testEventDict() -> [String: Any] {
  return [
    "className": "OmniClass",
    "methodName": "theMethod:toRule:themAll:",
  ]
}

final class FBLogicReporterAdapterTests: XCTestCase {

  var adapter: FBLogicReporterAdapter!
  var reporterDouble: FBXCTestReporterDouble!

  override func setUp() {
    super.setUp()
    reporterDouble = FBXCTestReporterDouble()
    adapter = FBLogicReporterAdapter(reporter: reporterDouble, logger: nil)
  }

  func test_LogicReporter_testSuiteDidStart() {
    let data = try! JSONSerialization.data(withJSONObject: beginTestSuiteDict())

    adapter.handleEventJSONData(data)
    XCTAssertEqual(reporterDouble.startedSuites, ["NARANJA"])
  }

  func test_LogicReporter_testCaseDidStart() {
    var event = testEventDict()
    event["event"] = "begin-test"

    let data = try! JSONSerialization.data(withJSONObject: event)
    adapter.handleEventJSONData(data)

    XCTAssertEqual(reporterDouble.startedTests, [[event["className"] as! String, event["methodName"] as! String]])
  }

  func test_LogicReporter_testCaseDidFail_fromFailure() {
    var event = testEventDict()
    let duration: TimeInterval = 0.0050642
    event["totalDuration"] = duration
    event["event"] = "end-test"
    event["result"] = "failure"

    let message = "The message to win all messages"
    let line = 969
    let file = "dasLiebstenFeile"
    event["exceptions"] = [
      [
        "reason": message,
        "lineNumber": line,
        "filePathInProject": file,
      ]
    ]

    let data = try! JSONSerialization.data(withJSONObject: event)
    adapter.handleEventJSONData(data)

    XCTAssertEqual(reporterDouble.failedTests, [[event["className"] as! String, event["methodName"] as! String]])
  }

  func test_LogicReporter_testCaseDidFail_fromError() {
    var event = testEventDict()
    let duration: TimeInterval = 0.0050642
    event["totalDuration"] = duration
    event["event"] = "end-test"
    event["result"] = "error"

    let message = "The message to win all messages"
    let line = 969
    let file = "dasLiebstenFeile"
    event["exceptions"] = [
      [
        "reason": message,
        "lineNumber": line,
        "filePathInProject": file,
      ]
    ]

    let data = try! JSONSerialization.data(withJSONObject: event)
    adapter.handleEventJSONData(data)

    XCTAssertEqual(reporterDouble.failedTests, [[event["className"] as! String, event["methodName"] as! String]])
  }

  func test_LogicReporter_testCaseDidSucceed() {
    var event = testEventDict()
    event["event"] = "begin-event"
    let duration: TimeInterval = 0.0050642
    event["totalDuration"] = duration
    event["event"] = "end-test"
    event["result"] = "success"

    let data = try! JSONSerialization.data(withJSONObject: event)
    adapter.handleEventJSONData(data)

    XCTAssertEqual(reporterDouble.passedTests, [[event["className"] as! String, event["methodName"] as! String]])
  }

  func test_LogicReporter_testSuiteDidEnd() {
    let dict: [String: Any] = [
      "event": "end-test-suite",
      "suite": "Toplevel Test Suite",
      "testCaseCount": 10,
      "testDuration": "0.148857057094574",
      "timestamp": "1510917478.156559",
      "totalDuration": "0.1503260135650635",
      "totalFailureCount": 4,
      "unexpectedExceptionCount": 0,
    ]

    let data = try! JSONSerialization.data(withJSONObject: dict)
    adapter.handleEventJSONData(data)

    XCTAssertEqual(reporterDouble.endedSuites, ["Toplevel Test Suite"])
  }
}
