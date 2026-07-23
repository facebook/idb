/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest
import XCTestBootstrap

final class FBJSONTestReporterTests: XCTestCase {

  private var mutableLines: NSMutableArray!
  var consumer: FBDataConsumer!
  var reporter: FBJSONTestReporter!

  var lines: [String] {
    return mutableLines as! [String]
  }

  override func setUp() {
    super.setUp()
    mutableLines = NSMutableArray()
    let linesRef = mutableLines!
    consumer = FBBlockDataConsumer.synchronousLineConsumer { line in
      linesRef.add(line)
    }
    reporter = FBJSONTestReporter(testBundlePath: "/path.bundle", testType: "footype", logger: nil, dataConsumer: consumer)
  }

  private func object(atLine index: Int) -> [String: Any] {
    let line = lines[index]
    let data = line.data(using: .utf8)!
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }

  subscript(index: Int) -> [String: Any] {
    return object(atLine: index)
  }

  func testReportsTests() {
    reporter.didBeginExecutingTestPlan()
    reporter.didFinishExecutingTestPlan()
    XCTAssertNoThrow(try reporter.printReport())

    XCTAssertEqual(lines.count, 2)
    XCTAssertEqual(self[0]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[0]["event"] as? String, "begin-ocunit")
    XCTAssertEqual(self[1]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[1]["event"] as? String, "end-ocunit")
    XCTAssertEqual(self[1]["succeeded"] as? Int, 1)
  }

  func testNoStartOfTestPlan() {
    reporter.didFinishExecutingTestPlan()
    XCTAssertThrowsError(try reporter.printReport())

    XCTAssertEqual(lines.count, 2)
    XCTAssertEqual(self[0]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[0]["event"] as? String, "begin-ocunit")
    XCTAssertEqual(self[1]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[1]["event"] as? String, "end-ocunit")
    XCTAssertEqual(self[1]["succeeded"] as? Int, 0)
    XCTAssertEqual(self[1]["message"] as? String, "No didBeginExecutingTestPlan event was received.")
  }

  func testReportTestSuccess() {
    reporter.didBeginExecutingTestPlan()
    reporter.testCaseDidStart(forTestClass: "FooTest", method: "BarCase")
    reporter.testCaseDidFinish(forTestClass: "FooTest", method: "BarCase", with: .passed, duration: 1, logs: nil)
    reporter.didFinishExecutingTestPlan()
    XCTAssertNoThrow(try reporter.printReport())

    XCTAssertEqual(lines.count, 4)
    XCTAssertEqual(self[0]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[0]["event"] as? String, "begin-ocunit")

    XCTAssertEqual(self[1]["className"] as? String, "FooTest")
    XCTAssertEqual(self[1]["methodName"] as? String, "BarCase")
    XCTAssertEqual(self[1]["event"] as? String, "begin-test")
    XCTAssertEqual(self[1]["test"] as? String, "-[FooTest BarCase]")

    XCTAssertEqual(self[2]["className"] as? String, "FooTest")
    XCTAssertEqual(self[2]["methodName"] as? String, "BarCase")
    XCTAssertEqual(self[2]["event"] as? String, "end-test")
    XCTAssertEqual(self[2]["test"] as? String, "-[FooTest BarCase]")
    XCTAssertEqual(self[2]["result"] as? String, "success")
    XCTAssertEqual(self[2]["succeeded"] as? Int, 1)

    XCTAssertEqual(self[3]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[3]["event"] as? String, "end-ocunit")
    XCTAssertEqual(self[3]["succeeded"] as? Int, 1)
  }

  func testReportMultipleTestCases() {
    let cases: [(String, String, FBTestReportStatus)] = [
      ("FooTest", "BarCase", .passed),
      ("BazTest", "CatCase", .failed),
      ("BingTest", "DogCase", .passed),
      ("BlipTest", "BagCase", .failed),
    ]

    reporter.didBeginExecutingTestPlan()
    for (testClass, method, status) in cases {
      reporter.testCaseDidStart(forTestClass: testClass, method: method)
      reporter.testCaseDidFinish(forTestClass: testClass, method: method, with: status, duration: 1, logs: nil)
    }
    reporter.didFinishExecutingTestPlan()
    XCTAssertNoThrow(try reporter.printReport())

    let count = 2 + (2 * cases.count)
    XCTAssertEqual(lines.count, count)
    XCTAssertEqual(self[0]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[0]["event"] as? String, "begin-ocunit")

    XCTAssertEqual(self[count - 1]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[count - 1]["event"] as? String, "end-ocunit")
    XCTAssertEqual(self[count - 1]["succeeded"] as? Int, 1)
  }

  func testReportTestFailure() {
    reporter.didBeginExecutingTestPlan()
    reporter.testCaseDidStart(forTestClass: "FooTest", method: "BarCase")
    reporter.testCaseDidFail(
      forTestClass: "FooTest", method: "BarCase",
      exceptions: [
        FBExceptionInfo(message: "BadBar", file: "BadFile", line: 42)
      ])
    reporter.testCaseDidFinish(forTestClass: "FooTest", method: "BarCase", with: .failed, duration: 1, logs: nil)
    reporter.didFinishExecutingTestPlan()
    XCTAssertNoThrow(try reporter.printReport())

    XCTAssertEqual(lines.count, 4)
    XCTAssertEqual(self[0]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[0]["event"] as? String, "begin-ocunit")

    XCTAssertEqual(self[1]["className"] as? String, "FooTest")
    XCTAssertEqual(self[1]["methodName"] as? String, "BarCase")
    XCTAssertEqual(self[1]["event"] as? String, "begin-test")
    XCTAssertEqual(self[1]["test"] as? String, "-[FooTest BarCase]")

    XCTAssertEqual(self[2]["className"] as? String, "FooTest")
    XCTAssertEqual(self[2]["methodName"] as? String, "BarCase")
    XCTAssertEqual(self[2]["event"] as? String, "end-test")
    XCTAssertEqual(self[2]["test"] as? String, "-[FooTest BarCase]")
    XCTAssertEqual(self[2]["result"] as? String, "failure")
    XCTAssertEqual(self[2]["succeeded"] as? Int, 0)
    XCTAssertEqual((self[2]["exceptions"] as? [[String: Any]])?[0]["reason"] as? String, "BadBar")

    XCTAssertEqual(self[3]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[3]["event"] as? String, "end-ocunit")
    XCTAssertEqual(self[3]["succeeded"] as? Int, 1)
  }

  func testReportTestOutput() {
    reporter.didBeginExecutingTestPlan()
    reporter.testCaseDidStart(forTestClass: "FooTest", method: "BarCase")
    reporter.testHadOutput("Some Output For Foo")
    reporter.testCaseDidFinish(forTestClass: "FooTest", method: "BarCase", with: .passed, duration: 1, logs: nil)
    reporter.didFinishExecutingTestPlan()
    XCTAssertNoThrow(try reporter.printReport())

    XCTAssertEqual(lines.count, 5)
    XCTAssertEqual(self[0]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[0]["event"] as? String, "begin-ocunit")

    XCTAssertEqual(self[1]["className"] as? String, "FooTest")
    XCTAssertEqual(self[1]["methodName"] as? String, "BarCase")
    XCTAssertEqual(self[1]["event"] as? String, "begin-test")
    XCTAssertEqual(self[1]["test"] as? String, "-[FooTest BarCase]")

    XCTAssertEqual(self[2]["event"] as? String, "test-output")
    XCTAssertEqual(self[2]["output"] as? String, "Some Output For Foo")

    XCTAssertEqual(self[3]["className"] as? String, "FooTest")
    XCTAssertEqual(self[3]["methodName"] as? String, "BarCase")
    XCTAssertEqual(self[3]["event"] as? String, "end-test")
    XCTAssertEqual(self[3]["test"] as? String, "-[FooTest BarCase]")
    XCTAssertEqual(self[3]["result"] as? String, "success")
    XCTAssertEqual(self[3]["succeeded"] as? Int, 1)

    XCTAssertEqual(self[4]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[4]["event"] as? String, "end-ocunit")
    XCTAssertEqual(self[4]["succeeded"] as? Int, 1)
  }

  func testBundleCrashIfNoDidFinish() {
    reporter.didBeginExecutingTestPlan()
    reporter.testCaseDidStart(forTestClass: "FooTest", method: "BarCase")
    reporter.testCaseDidFinish(forTestClass: "FooTest", method: "BarCase", with: .failed, duration: 1, logs: nil)
    XCTAssertThrowsError(try reporter.printReport())

    XCTAssertEqual(lines.count, 4)
    XCTAssertEqual(self[0]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[0]["event"] as? String, "begin-ocunit")

    XCTAssertEqual(self[1]["className"] as? String, "FooTest")
    XCTAssertEqual(self[1]["methodName"] as? String, "BarCase")
    XCTAssertEqual(self[1]["event"] as? String, "begin-test")
    XCTAssertEqual(self[1]["test"] as? String, "-[FooTest BarCase]")

    XCTAssertEqual(self[2]["className"] as? String, "FooTest")
    XCTAssertEqual(self[2]["methodName"] as? String, "BarCase")
    XCTAssertEqual(self[2]["event"] as? String, "end-test")
    XCTAssertEqual(self[2]["test"] as? String, "-[FooTest BarCase]")

    XCTAssertEqual(self[3]["bundleName"] as? String, "path.bundle")
    XCTAssertEqual(self[3]["message"] as? String, "No didFinishExecutingTestPlan event was received, the test bundle has likely crashed.")
    XCTAssertEqual(self[3]["succeeded"] as? Int, 0)
    XCTAssertEqual(self[3]["event"] as? String, "end-ocunit")
  }
}
