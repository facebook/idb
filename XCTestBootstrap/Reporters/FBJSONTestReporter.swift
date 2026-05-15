/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private func fullyFormattedXCTestName(_ className: String, _ methodName: String) -> String {
  return "-[\(className) \(methodName)]"
}

@objc public final class FBJSONTestReporter: NSObject, FBXCTestReporter {

  private let dataConsumer: FBDataConsumer
  private let logger: FBControlCoreLogger?
  private let testBundlePath: String
  private let testType: String
  private var events: [[String: Any]] = []
  private var xctestNameExceptionsMapping: [String: [[String: Any]]] = [:]
  private var pendingTestOutput: [String] = []

  private var currentTestName: String?
  private var crashError: Error?
  private var started: Bool = false
  private var finished: Bool = false

  @objc public init(testBundlePath: String, testType: String, logger: FBControlCoreLogger?, dataConsumer: FBDataConsumer) {
    self.dataConsumer = dataConsumer
    self.logger = logger
    self.testBundlePath = testBundlePath
    self.testType = testType
    super.init()
  }

  // MARK: FBXCTestReporter

  @objc public func printReport() throws {
    if !started {
      throw XCTestBootstrapError.describe(noStartOfTestPlanErrorMessage()).build()
    }
    if !finished {
      var errorMessage = "No didFinishExecutingTestPlan event was received, the test bundle has likely crashed."
      if let crashError {
        errorMessage = crashError.localizedDescription
      }
      if let currentTestName {
        errorMessage += ". Crash occurred while this test was running: \(currentTestName)"
      }
      printEvent(FBJSONTestReporter.createOCUnitEndEvent(testType, testBundlePath: testBundlePath, message: errorMessage, success: false))
      throw XCTestBootstrapError.describe(errorMessage).build()
    }
    dataConsumer.consumeEndOfFile()
  }

  @objc public func processWaitingForDebugger(withProcessIdentifier pid: pid_t) {
    printEvent(FBJSONTestReporter.waitingForDebuggerEvent(pid))
  }

  @objc public func didBeginExecutingTestPlan() {
    started = true
    printEvent(FBJSONTestReporter.createOCUnitBeginEvent(testType, testBundlePath: testBundlePath))
  }

  @objc public func didFinishExecutingTestPlan() {
    if started {
      printEvent(FBJSONTestReporter.createOCUnitEndEvent(testType, testBundlePath: testBundlePath, message: nil, success: true))
    } else {
      printEvent(FBJSONTestReporter.createOCUnitBeginEvent(testType, testBundlePath: testBundlePath))
      let errorMessage = noStartOfTestPlanErrorMessage()
      printEvent(FBJSONTestReporter.createOCUnitEndEvent(testType, testBundlePath: testBundlePath, message: errorMessage, success: false))
    }
    finished = true
  }

  @objc public func testSuite(_ testSuite: String, didStartAt startTime: String) {
    printEvent(FBJSONTestReporter.beginTestSuiteEvent(testSuite))
  }

  @objc public func testCaseDidStart(forTestClass testClass: String, method: String) {
    let xctestName = fullyFormattedXCTestName(testClass, method)
    currentTestName = xctestName
    xctestNameExceptionsMapping[xctestName] = []
    printEvent(FBJSONTestReporter.beginTestCaseEvent(testClass, testMethod: method))
  }

  @objc public func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [FBExceptionInfo]) {
    let xctestName = fullyFormattedXCTestName(testClass, method)
    for exception in exceptions {
      xctestNameExceptionsMapping[xctestName]?.append(FBJSONTestReporter.exceptionEvent(exception.message, file: exception.file ?? "", line: exception.line))
    }
  }

  @objc public func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?) {
    currentTestName = nil
    let event = FBJSONTestReporter.testCaseDidFinishEvent(forTestClass: testClass, method: method, status: status, duration: duration, pendingTestOutput: pendingTestOutput, xctestNameExceptionsMapping: xctestNameExceptionsMapping)
    printEvent(event)
    pendingTestOutput.removeAll()
  }

  @objc public func finished(with summary: FBTestManagerResultSummary) {
    printEvent(FBJSONTestReporter.finishedEvent(from: summary))
  }

  @objc public func didRecordVideo(atPath videoRecordingPath: String) {
    printEvent([
      "event": "video-recording-finished",
      "videoRecordingPath": videoRecordingPath,
    ])
  }

  @objc public func didSaveOSLog(atPath osLogPath: String) {
    printEvent([
      "event": "os-log-saved",
      "osLogPath": osLogPath,
    ])
  }

  @objc public func didCopiedTestArtifact(_ testArtifactFilename: String, toPath path: String) {
    printEvent([
      "event": "copy-test-artifact",
      "test_artifact_file_name": testArtifactFilename,
      "path": path,
    ])
  }

  @objc public func testHadOutput(_ output: String) {
    pendingTestOutput.append(output)
    printEvent(FBJSONTestReporter.testOutputEvent(output))
  }

  @objc public func handleExternalEvent(_ line: String) {
    if line.isEmpty {
      return
    }
    guard let data = line.data(using: .utf8),
      var event = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    else {
      logger?.log("Received unexpected output from otest-shim:\n\(line)")
      return
    }
    if event["event"] as? String == "end-test" {
      event["output"] = pendingTestOutput.joined()
      pendingTestOutput.removeAll()
    }
    events.append(event)
  }

  @objc public func processUnderTestDidExit() {}

  @objc public func didCrashDuringTest(_ error: Error) {
    crashError = error
  }

  // MARK: Private

  private func printEvent(_ event: [String: Any]) {
    var timestamped = event
    if timestamped["timestamp"] == nil {
      timestamped["timestamp"] = Date().timeIntervalSince1970
    }
    if let data = try? JSONSerialization.data(withJSONObject: timestamped, options: []) {
      dataConsumer.consumeData(data)
      dataConsumer.consumeData(Data("\n".utf8))
    }
  }

  private func noStartOfTestPlanErrorMessage() -> String {
    var errorMessage = "No didBeginExecutingTestPlan event was received."
    if let currentTestName {
      errorMessage += ". However a test was running: \(currentTestName)"
    }
    return errorMessage
  }

  private static func exceptionEvent(_ reason: String, file: String, line: UInt) -> [String: Any] {
    return [
      "lineNumber": line,
      "filePathInProject": file,
      "reason": reason,
    ]
  }

  private static func beginTestCaseEvent(_ testClass: String, testMethod method: String) -> [String: Any] {
    return [
      "event": "begin-test",
      "className": testClass,
      "methodName": method,
      "test": fullyFormattedXCTestName(testClass, method),
    ]
  }

  private static func beginTestSuiteEvent(_ testSuite: String) -> [String: Any] {
    return [
      "event": "begin-test-suite",
      "suite": testSuite,
    ]
  }

  private static func testOutputEvent(_ output: String) -> [String: Any] {
    return [
      "event": "test-output",
      "output": output,
    ]
  }

  private static func waitingForDebuggerEvent(_ pid: pid_t) -> [String: Any] {
    return [
      "event": "begin-status",
      "pid": pid,
      "level": "Info",
      "message": "Tests waiting for debugger. To debug run: lldb -p \(pid)",
    ]
  }

  private static func createOCUnitBeginEvent(_ testType: String, testBundlePath: String) -> [String: Any] {
    return [
      "event": "begin-ocunit",
      "testType": testType,
      "bundleName": (testBundlePath as NSString).lastPathComponent,
      "targetName": testBundlePath,
    ]
  }

  private static func createOCUnitEndEvent(_ testType: String, testBundlePath: String, message: String?, success: Bool) -> [String: Any] {
    var event: [String: Any] = [
      "event": "end-ocunit",
      "testType": testType,
      "bundleName": (testBundlePath as NSString).lastPathComponent,
      "targetName": testBundlePath,
      "succeeded": success,
    ]
    if let message {
      event["message"] = message
    }
    return event
  }

  private static func finishedEvent(from summary: FBTestManagerResultSummary) -> [String: Any] {
    return [
      "event": "end-test-suite",
      "suite": summary.testSuite,
      "testCaseCount": summary.runCount,
      "totalFailureCount": summary.failureCount,
      "totalDuration": summary.totalDuration,
      "unexpectedExceptionCount": summary.unexpected,
      "testDuration": summary.testDuration,
    ]
  }

  private static func testCaseDidFinishEvent(forTestClass testClass: String, method: String, status: FBTestReportStatus, duration: TimeInterval, pendingTestOutput: [String], xctestNameExceptionsMapping: [String: [[String: Any]]]) -> [String: Any] {
    let xctestName = fullyFormattedXCTestName(testClass, method)
    return [
      "event": "end-test",
      "result": (status == .passed ? "success" : "failure"),
      "output": pendingTestOutput.joined(),
      "test": xctestName,
      "className": testClass,
      "methodName": method,
      "succeeded": (status == .passed),
      "exceptions": xctestNameExceptionsMapping[xctestName] ?? [],
      "totalDuration": duration,
    ]
  }
}
