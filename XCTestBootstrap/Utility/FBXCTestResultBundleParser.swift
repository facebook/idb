/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let XCTestOperationTimeoutSecs: TimeInterval = 120

// MARK: Helper functions

private func readFromDict(_ dict: NSDictionary, _ key: String) -> Any {
  guard let val = dict[key] else {
    preconditionFailure("\(key) is not present in dict")
  }
  return val
}

private func readNumberFromDict(_ dict: NSDictionary, _ key: String) -> NSNumber {
  guard let val = readFromDict(dict, key) as? NSNumber else {
    preconditionFailure("\(key) is not a NSNumber")
  }
  return val
}

private func readDoubleFromDict(_ dict: NSDictionary, _ key: String) -> Double {
  return readNumberFromDict(dict, key).doubleValue
}

private func readStringFromDict(_ dict: NSDictionary, _ key: String) -> String {
  guard let val = readFromDict(dict, key) as? String else {
    preconditionFailure("\(key) is not a NSString")
  }
  return val
}

private func readArrayFromDict(_ dict: NSDictionary, _ key: String) -> NSArray {
  guard let val = readFromDict(dict, key) as? NSArray else {
    preconditionFailure("\(key) is not a NSArray")
  }
  return val
}

private func unwrapValues(_ wrapped: NSDictionary) -> NSArray? {
  return wrapped["_values"] as? NSArray
}

private func unwrapValue(_ wrapped: NSDictionary) -> Any? {
  return wrapped["_value"]
}

private func accessAndUnwrapValues(_ dict: NSDictionary, _ key: String, _ logger: FBControlCoreLogger) -> NSArray? {
  guard let wrapped = dict[key] as? NSDictionary else {
    logger.log("\(key) does not exist inside \(FBCollectionInformation.oneLineDescription(from: dict.allKeys))")
    return nil
  }
  let unwrapped = unwrapValues(wrapped)
  if unwrapped == nil {
    logger.log("Failed to unwrap values for \(key) from \(FBCollectionInformation.oneLineDescription(from: wrapped.allKeys))")
  }
  return unwrapped
}

private func accessAndUnwrapValue(_ dict: NSDictionary, _ key: String, _ logger: FBControlCoreLogger) -> Any? {
  guard let wrapped = dict[key] as? NSDictionary else {
    logger.log("\(key) does not exist inside \(FBCollectionInformation.oneLineDescription(from: dict.allKeys))")
    return nil
  }
  let unwrapped = unwrapValue(wrapped)
  if unwrapped == nil {
    logger.log("Failed to unwrap value for \(key) from \(FBCollectionInformation.oneLineDescription(from: wrapped.allKeys))")
  }
  return unwrapped
}

private func dateFromString(_ date: String) -> Date? {
  let dateFormatter = DateFormatter()
  dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
  return dateFormatter.date(from: date)
}

@objc public final class FBXCTestResultBundleParser: NSObject {

  // MARK: Public

  @objc public static func parse(_ resultBundlePath: String, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, extractScreenshots: Bool) -> FBFuture<NSNull> {
    logger.log("Parsing the result bundle \(resultBundlePath)")

    let testSummariesPath = (resultBundlePath as NSString).appendingPathComponent("TestSummaries.plist")
    let results = NSDictionary(contentsOfFile: testSummariesPath)
    let resultBundleInfoPath = (resultBundlePath as NSString).appendingPathComponent("Info.plist")
    let bundleInfo = NSDictionary(contentsOfFile: resultBundleInfoPath)
    let bundleFormatVersion = bundleInfo?["version"]

    if let results {
      reportResultsLegacy(results, reporter: reporter)
      logger.log("ResultBundlePath: \(resultBundlePath)")
      return FBFuture(result: NSNull())
    } else if let bundleFormatVersion = bundleFormatVersion as? NSDictionary {
      let majorVersion = readNumberFromDict(bundleFormatVersion, "major")
      let minorVersion = readNumberFromDict(bundleFormatVersion, "minor")
      logger.log("Test result bundle format version: \(majorVersion).\(minorVersion)")
      return unsafeBitCast(
        unsafeBitCast(
          FBXCTestResultToolOperation.getJSON(from: resultBundlePath, forId: nil, queue: target.workQueue, logger: logger),
          to: FBFuture<AnyObject>.self
        )
        .onQueue(
          target.workQueue,
          fmap: { actionsInvocationRecord -> FBFuture<AnyObject> in
            let record = actionsInvocationRecord as! NSDictionary
            let actions = record["actions"] as! NSDictionary
            let ids = parseActions(actions, logger: logger)
            var operations: [AnyObject] = []
            for bundleObjectId in ids {
              let operation = unsafeBitCast(
                FBXCTestResultToolOperation.getJSON(from: resultBundlePath, forId: bundleObjectId, queue: target.workQueue, logger: logger),
                to: FBFuture<AnyObject>.self
              )
              .onQueue(
                target.workQueue,
                doOnResolved: { xcresults in
                  let xcresultsDict = xcresults as! NSDictionary
                  logger.log("Parsing summaries for id \(bundleObjectId)")
                  let summaries = accessAndUnwrapValues(xcresultsDict, "summaries", logger)
                  reportSummaries(summaries, reporter: reporter, queue: target.asyncQueue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
                  logger.log("Done parsing summaries for id \(bundleObjectId)")
                })
              operations.append(operation as AnyObject)
            }
            // futureWithFutures: is NS_SWIFT_UNAVAILABLE, use ObjC runtime
            let selector = NSSelectorFromString("futureWithFutures:")
            let cls: AnyClass = FBFuture<NSArray>.self
            let method = (cls as AnyObject).method(for: selector)
            typealias CombineFunc = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
            let combine = unsafeBitCast(method, to: CombineFunc.self)
            return combine(cls as AnyObject, selector, operations as NSArray)
          }),
        to: FBFuture<NSNull>.self
      )
    } else {
      reporter.testPlanDidFail?(withMessage: "No test results were produced")
      return FBFuture(result: NSNull())
    }
  }

  // MARK: Private: Legacy XCTest Result Parsing

  private static func reportResultsLegacy(_ results: NSDictionary, reporter: FBXCTestReporter) {
    let testTargets = results["TestableSummaries"] as? [NSDictionary]
    reportTargetTestsLegacy(testTargets, reporter: reporter)
  }

  private static func reportTargetTestsLegacy(_ targetTests: [NSDictionary]?, reporter: FBXCTestReporter) {
    guard let targetTests else { return }
    for targetTest in targetTests {
      reportTargetTestLegacy(targetTest, reporter: reporter)
    }
  }

  private static func reportTargetTestLegacy(_ targetTest: NSDictionary, reporter: FBXCTestReporter) {
    let testBundleName = readStringFromDict(targetTest, "TestName")
    let selectedTests = targetTest["Tests"] as? [NSDictionary]
    reportSelectedTestsLegacy(selectedTests, testBundleName: testBundleName, reporter: reporter)
  }

  private static func reportSelectedTestsLegacy(_ selectedTests: [NSDictionary]?, testBundleName: String, reporter: FBXCTestReporter) {
    guard let selectedTests else { return }
    for selectedTest in selectedTests {
      reportSelectedTestLegacy(selectedTest, testBundleName: testBundleName, reporter: reporter)
    }
  }

  private static func reportSelectedTestLegacy(_ selectedTest: NSDictionary, testBundleName: String, reporter: FBXCTestReporter) {
    let testTargetXctests = selectedTest["Subtests"] as? [NSDictionary]
    reportTestTargetXctestsLegacy(testTargetXctests, testBundleName: testBundleName, reporter: reporter)
  }

  private static func reportTestTargetXctestsLegacy(_ testTargetXctests: [NSDictionary]?, testBundleName: String, reporter: FBXCTestReporter) {
    guard let testTargetXctests else { return }
    for testTargetXctest in testTargetXctests {
      reportTestTargetXctestLegacy(testTargetXctest, testBundleName: testBundleName, reporter: reporter)
    }
  }

  private static func reportTestTargetXctestLegacy(_ testTargetXctest: NSDictionary, testBundleName: String, reporter: FBXCTestReporter) {
    let testClasses = testTargetXctest["Subtests"] as? [NSDictionary]
    reportTestClassesLegacy(testClasses, testBundleName: testBundleName, reporter: reporter)
  }

  private static func reportTestClassesLegacy(_ testClasses: [NSDictionary]?, testBundleName: String, reporter: FBXCTestReporter) {
    guard let testClasses else { return }
    for testClass in testClasses {
      reportTestClassLegacy(testClass, testBundleName: testBundleName, reporter: reporter)
    }
  }

  private static func reportTestClassLegacy(_ testClass: NSDictionary, testBundleName: String, reporter: FBXCTestReporter) {
    let testClassName = readStringFromDict(testClass, "TestIdentifier")
    let testMethods = testClass["Subtests"] as? [NSDictionary]
    reportTestMethodsLegacy(testMethods, testBundleName: testBundleName, testClassName: testClassName, reporter: reporter)
  }

  private static func reportTestMethodsLegacy(_ testMethods: [NSDictionary]?, testBundleName: String, testClassName: String, reporter: FBXCTestReporter) {
    guard let testMethods else { return }
    for testMethod in testMethods {
      reportTestMethodLegacy(testMethod, testBundleName: testBundleName, testClassName: testClassName, reporter: reporter)
    }
  }

  private static func reportTestMethodLegacy(_ testMethod: NSDictionary, testBundleName: String, testClassName: String, reporter: FBXCTestReporter) {
    let testStatus = readStringFromDict(testMethod, "TestStatus")
    let testMethodName = readStringFromDict(testMethod, "TestIdentifier")
    let duration = readNumberFromDict(testMethod, "Duration")

    var status = FBTestReportStatus.unknown
    if testStatus == "Success" {
      status = .passed
    }
    if testStatus == "Failure" {
      status = .failed
    }

    let activitySummaries = readArrayFromDict(testMethod, "ActivitySummaries") as! [NSDictionary]
    let logs = buildTestLogLegacy(activitySummaries, testBundleName: testBundleName, testClassName: testClassName, testMethodName: testMethodName, testPassed: status == .passed, duration: duration.doubleValue)

    reporter.testCaseDidStart(forTestClass: testClassName, method: testMethodName)
    if status == .failed {
      let failureSummaries = readArrayFromDict(testMethod, "FailureSummaries") as! [NSDictionary]
      reporter.testCaseDidFail(
        forTestClass: testClassName, method: testMethodName,
        exceptions: [
          FBExceptionInfo(message: buildErrorMessageLegacy(failureSummaries))
        ])
    }
    reporter.testCaseDidFinish(forTestClass: testClassName, method: testMethodName, with: status, duration: duration.doubleValue, logs: logs)
  }

  private static func buildTestLogLegacy(_ activitySummaries: [NSDictionary], testBundleName: String, testClassName: String, testMethodName: String, testPassed: Bool, duration: Double) -> [String] {
    var logs: [String] = []
    let testCaseFullName = "-[\(testBundleName).\(testClassName) \(testMethodName)]"
    logs.append("Test Case '\(testCaseFullName)' started.")

    var testStartTimeInterval: Double = 0
    var startTimeSet = false
    for activitySummary in activitySummaries {
      if !startTimeSet {
        testStartTimeInterval = readDoubleFromDict(activitySummary, "StartTimeInterval")
        startTimeSet = true
      }

      let activityType = readStringFromDict(activitySummary, "ActivityType")
      if activityType == "com.apple.dt.xctest.activity-type.internal" {
        addTestLogsFromLegacyActivitySummary(activitySummary, logs: &logs, testStartTimeInterval: testStartTimeInterval, indent: 0)
      }
    }

    logs.append("Test Case '\(testCaseFullName)' \(testPassed ? "passed" : "failed") in \(String(format: "%.3f", duration)) seconds")
    return logs
  }

  private static func addTestLogsFromLegacyActivitySummary(_ activitySummary: NSDictionary, logs: inout [String], testStartTimeInterval: Double, indent: UInt) {
    let message = readStringFromDict(activitySummary, "Title")
    let startTimeInterval = readDoubleFromDict(activitySummary, "StartTimeInterval")
    let elapsed = startTimeInterval - testStartTimeInterval
    let indentString = "".padding(toLength: 1 + Int(indent) * 4, withPad: " ", startingAt: 0)
    let log = String(format: "    t = %8.2fs%@%@", elapsed, indentString, message)
    logs.append(log)

    guard let subActivities = activitySummary["SubActivities"] as? [NSDictionary] else {
      return
    }
    for subActivity in subActivities {
      addTestLogsFromLegacyActivitySummary(subActivity, logs: &logs, testStartTimeInterval: testStartTimeInterval, indent: indent + 1)
    }
  }

  private static func buildErrorMessageLegacy(_ failureSummaries: [NSDictionary]) -> String {
    var messages: [String] = []
    for failureSummary in failureSummaries {
      messages.append(readStringFromDict(failureSummary, "Message"))
    }
    return messages.joined(separator: "\n")
  }

  // MARK: Private: Xcode 11+ XCTest Result Parsing

  private static func parseActions(_ actions: NSDictionary, logger: FBControlCoreLogger) -> [String] {
    guard let actionValues = unwrapValues(actions) as? [NSDictionary] else {
      preconditionFailure("action values is nil")
    }
    var ids: [String] = []
    for action in actionValues {
      ids.append(parseAction(action, logger: logger))
    }
    return ids
  }

  private static func parseAction(_ action: NSDictionary, logger: FBControlCoreLogger) -> String {
    let actionResult = action["actionResult"] as! NSDictionary
    return parseActionResult(actionResult, logger: logger)
  }

  private static func parseActionResult(_ actionResult: NSDictionary, logger: FBControlCoreLogger) -> String {
    let testsRef = actionResult["testsRef"] as! NSDictionary
    return parseTestsRef(testsRef, logger: logger)
  }

  private static func parseTestsRef(_ testsRef: NSDictionary, logger: FBControlCoreLogger) -> String {
    return accessAndUnwrapValue(testsRef, "id", logger) as! String
  }

  private static func reportSummaries(_ summaries: NSArray?, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    guard let summaries = summaries as? [NSDictionary] else { return }
    for summary in summaries {
      reportResults(summary, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportResults(_ results: NSDictionary, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    let testTargets = accessAndUnwrapValues(results, "testableSummaries", logger)
    reportTargetTests(testTargets, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
  }

  private static func reportTargetTests(_ targetTests: NSArray?, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    guard let targetTests = targetTests as? [NSDictionary] else { return }
    for targetTest in targetTests {
      reportTargetTest(targetTest, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportTargetTest(_ targetTest: NSDictionary, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    let testBundleName = accessAndUnwrapValue(targetTest, "targetName", logger) as? String ?? ""
    let selectedTests = accessAndUnwrapValues(targetTest, "tests", logger)
    if selectedTests != nil {
      reportSelectedTests(selectedTests, testBundleName: testBundleName, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    } else {
      logger.log("Test failed and no test results found in the bundle")
      let failureSummaries = accessAndUnwrapValues(targetTest, "failureSummaries", logger)
      reporter.testCaseDidFail(
        forTestClass: "", method: "",
        exceptions: [
          FBExceptionInfo(message: buildErrorMessage(failureSummaries, logger: logger))
        ])
    }
  }

  private static func reportSelectedTests(_ selectedTests: NSArray?, testBundleName: String, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    guard let selectedTests = selectedTests as? [NSDictionary] else { return }
    for selectedTest in selectedTests {
      reportSelectedTest(selectedTest, testBundleName: testBundleName, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportSelectedTest(_ selectedTest: NSDictionary, testBundleName: String, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    let testTargetXctests = accessAndUnwrapValues(selectedTest, "subtests", logger)
    if testTargetXctests != nil {
      reportTestTargetXctests(testTargetXctests, testBundleName: testBundleName, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    } else {
      logger.log("Test failed and no target test results found in the bundle")
      reporter.testCaseDidFail(
        forTestClass: "", method: "",
        exceptions: [
          FBExceptionInfo(message: "")
        ])
    }
  }

  private static func reportTestTargetXctests(_ testTargetXctests: NSArray?, testBundleName: String, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    guard let testTargetXctests = testTargetXctests as? [NSDictionary] else { return }
    for testTargetXctest in testTargetXctests {
      reportTestTargetXctest(testTargetXctest, testBundleName: testBundleName, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportTestTargetXctest(_ testTargetXctest: NSDictionary, testBundleName: String, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    let testClasses = accessAndUnwrapValues(testTargetXctest, "subtests", logger)
    if testClasses != nil {
      reportTestClasses(testClasses, testBundleName: testBundleName, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    } else {
      logger.log("Test failed and no test class results found in the bundle")
      reporter.testCaseDidFail(
        forTestClass: "", method: "",
        exceptions: [
          FBExceptionInfo(message: "")
        ])
    }
  }

  private static func reportTestClasses(_ testClasses: NSArray?, testBundleName: String, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    guard let testClasses = testClasses as? [NSDictionary] else { return }
    for testClass in testClasses {
      reportTestClass(testClass, testBundleName: testBundleName, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportTestClass(_ testClass: NSDictionary, testBundleName: String, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    let testClassName = accessAndUnwrapValue(testClass, "identifier", logger) as? String ?? ""
    let testMethods = accessAndUnwrapValues(testClass, "subtests", logger)
    if testMethods != nil {
      reportTestMethods(testMethods, testBundleName: testBundleName, testClassName: testClassName, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    } else {
      logger.log("Test failed for \(testClassName) and no test method results found")
      reporter.testCaseDidFail(
        forTestClass: "", method: "",
        exceptions: [
          FBExceptionInfo(message: "")
        ])
    }
  }

  private static func reportTestMethods(_ testMethods: NSArray?, testBundleName: String, testClassName: String, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    guard let testMethods = testMethods as? [NSDictionary] else { return }
    for testMethod in testMethods {
      reportTestMethod(testMethod, testBundleName: testBundleName, testClassName: testClassName, reporter: reporter, queue: queue, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportTestMethod(_ testMethod: NSDictionary, testBundleName: String, testClassName: String, reporter: FBXCTestReporter, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger, extractScreenshots: Bool) {
    let testStatus = accessAndUnwrapValue(testMethod, "testStatus", logger) as? String ?? ""
    let testMethodIdentifier = accessAndUnwrapValue(testMethod, "identifier", logger) as? String ?? ""
    let duration = accessAndUnwrapValue(testMethod, "duration", logger) as? NSNumber ?? 0

    var status = FBTestReportStatus.unknown
    if testStatus == "Success" {
      status = .passed
    }
    if testStatus == "Failure" {
      status = .failed
    }

    reporter.testCaseDidStart(forTestClass: testClassName, method: testMethodIdentifier)

    let summaryRef = testMethod["summaryRef"] as? NSDictionary
    if let summaryRef, let summaryRefId = accessAndUnwrapValue(summaryRef, "id", logger) as? String {
      let future = unsafeBitCast(
        FBXCTestResultToolOperation.getJSON(from: resultBundlePath, forId: summaryRefId, queue: queue, logger: logger),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        queue,
        doOnResolved: { actionTestSummaryObj in
          let actionTestSummary = actionTestSummaryObj as! NSDictionary
          if status == .failed {
            let failureSummaries = accessAndUnwrapValues(actionTestSummary, "failureSummaries", logger)
            reporter.testCaseDidFail(
              forTestClass: testClassName, method: testMethodIdentifier,
              exceptions: [
                FBExceptionInfo(message: buildErrorMessage(failureSummaries, logger: logger))
              ])
          }

          let performanceMetrics = accessAndUnwrapValues(actionTestSummary, "performanceMetrics", logger) as? [NSDictionary]
          if let performanceMetrics {
            var testMethodName = accessAndUnwrapValue(testMethod, "name", logger) as? String ?? ""
            let suffix = "()"
            if testMethodName.hasSuffix(suffix) {
              testMethodName = String(testMethodName.dropLast(suffix.count))
            }
            savePerformanceMetrics(performanceMetrics, toTestResultBundle: resultBundlePath, forTestTarget: testBundleName, testClass: testClassName, testMethod: testMethodName, logger: logger)
          }

          let activitySummaries = accessAndUnwrapValues(actionTestSummary, "activitySummaries", logger) as? [NSDictionary]
          if extractScreenshots, let activitySummaries {
            extractScreenshotsFromActivities(activitySummaries, queue: queue, resultBundlePath: resultBundlePath, logger: logger)
          }

          let logs = buildTestLog(accessAndUnwrapValues(actionTestSummary, "activitySummaries", logger) as? [NSDictionary], testBundleName: testBundleName, testClassName: testClassName, testMethodName: testMethodIdentifier, testPassed: status == .passed, duration: duration.doubleValue, logger: logger)
          reporter.testCaseDidFinish(forTestClass: testClassName, method: testMethodIdentifier, with: status, duration: duration.doubleValue, logs: logs)
        })
      _ = try? future.await(withTimeout: XCTestOperationTimeoutSecs)
    }
  }

  private static func buildTestLog(_ activitySummaries: [NSDictionary]?, testBundleName: String, testClassName: String, testMethodName: String, testPassed: Bool, duration: Double, logger: FBControlCoreLogger) -> [String] {
    var logs: [String] = []
    let testCaseFullName = "-[\(testBundleName).\(testClassName) \(testMethodName)]"
    logs.append("Test Case '\(testCaseFullName)' started.")

    var testStartTimeInterval: Double = 0
    var startTimeSet = false
    for activitySummary in activitySummaries ?? [] {
      if !startTimeSet {
        if let dateStr = accessAndUnwrapValue(activitySummary, "start", logger) as? String, let date = dateFromString(dateStr) {
          testStartTimeInterval = date.timeIntervalSince1970
          startTimeSet = true
        }
      }

      let activityType = accessAndUnwrapValue(activitySummary, "activityType", logger) as? String
      if activityType == "com.apple.dt.xctest.activity-type.internal" {
        addTestLogsFromActivitySummary(activitySummary, logs: &logs, testStartTimeInterval: testStartTimeInterval, indent: 0, logger: logger)
      }
    }

    logs.append("Test Case '\(testCaseFullName)' \(testPassed ? "passed" : "failed") in \(String(format: "%.3f", duration)) seconds")
    return logs
  }

  private static func addTestLogsFromActivitySummary(_ activitySummary: NSDictionary, logs: inout [String], testStartTimeInterval: Double, indent: UInt, logger: FBControlCoreLogger) {
    let message = accessAndUnwrapValue(activitySummary, "title", logger) as? String ?? ""
    let dateStr = accessAndUnwrapValue(activitySummary, "start", logger) as? String ?? ""
    let date = dateFromString(dateStr)
    let startTimeInterval = date?.timeIntervalSince1970 ?? 0
    let elapsed = startTimeInterval - testStartTimeInterval
    let indentString = "".padding(toLength: 1 + Int(indent) * 4, withPad: " ", startingAt: 0)
    let log = String(format: "    t = %8.2fs%@%@", elapsed, indentString, message)
    logs.append(log)

    guard let wrappedSubActivities = activitySummary["subactivities"] as? NSDictionary,
      let subActivities = unwrapValues(wrappedSubActivities) as? [NSDictionary]
    else {
      return
    }
    for subActivity in subActivities {
      addTestLogsFromActivitySummary(subActivity, logs: &logs, testStartTimeInterval: testStartTimeInterval, indent: indent + 1, logger: logger)
    }
  }

  private static func extractScreenshotsFromActivities(_ activities: [NSDictionary], queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger) {
    let screenshotsPath: String
    do {
      screenshotsPath = try ensureSubdirectory("Attachments", insideResultBundle: resultBundlePath)
    } catch {
      logger.log("Failed to ensure attachments directory \(error)")
      return
    }
    for activity in activities {
      if activity["attachments"] != nil {
        if let attachments = accessAndUnwrapValues(activity, "attachments", logger) as? [NSDictionary] {
          extractScreenshotsFromAttachments(attachments, to: screenshotsPath, queue: queue, resultBundlePath: resultBundlePath, logger: logger)
        }
      }
      if activity["subactivities"] != nil {
        if let subactivities = accessAndUnwrapValues(activity, "subactivities", logger) as? [NSDictionary] {
          extractScreenshotsFromActivities(subactivities, queue: queue, resultBundlePath: resultBundlePath, logger: logger)
        }
      }
    }
  }

  private static func ensureSubdirectory(_ subdirectory: String, insideResultBundle resultBundlePath: String) throws -> String {
    let fileManager = FileManager.default
    let subdirectoryFullPath = (resultBundlePath as NSString).appendingPathComponent(subdirectory)
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: subdirectoryFullPath, isDirectory: &isDirectory) {
      if !isDirectory.boolValue {
        throw FBControlCoreError.describe("\(subdirectoryFullPath) is not a directory").build()
      }
    } else {
      try fileManager.createDirectory(atPath: subdirectoryFullPath, withIntermediateDirectories: false, attributes: nil)
    }
    return subdirectoryFullPath
  }

  private static func extractScreenshotsFromAttachments(_ attachments: [NSDictionary], to destination: String, queue: DispatchQueue, resultBundlePath: String, logger: FBControlCoreLogger) {
    guard let regex = try? NSRegularExpression(pattern: "^Screenshot_.*", options: []) else { return }
    for attachment in attachments {
      guard let filename = accessAndUnwrapValue(attachment, "filename", logger) as? String else { continue }
      let matchResult = regex.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: (filename as NSString).length))
      if attachment["payloadRef"] != nil && matchResult != nil {
        let timestamp = accessAndUnwrapValue(attachment, "timestamp", logger) as? String ?? ""
        let jpgFilename = (filename as NSString).deletingPathExtension.appending(".jpg")
        let exportPath = (destination as NSString).appendingPathComponent("\(timestamp)_\(jpgFilename)")
        let payloadRef = attachment["payloadRef"] as! NSDictionary
        let screenshotId = accessAndUnwrapValue(payloadRef, "id", logger) as! String
        let screenshotType = accessAndUnwrapValue(attachment, "uniformTypeIdentifier", logger) as! String
        _ = try? FBXCTestResultToolOperation.exportJPEG(from: resultBundlePath, to: exportPath, forId: screenshotId, type: screenshotType, queue: queue, logger: logger).await(withTimeout: XCTestOperationTimeoutSecs)
      }
    }
  }

  private static func savePerformanceMetrics(_ performanceMetrics: [NSDictionary], toTestResultBundle resultBundlePath: String, forTestTarget testTarget: String, testClass: String, testMethod: String, logger: FBControlCoreLogger) {
    var metrics: [[String: Any]] = []
    for performanceMetric in performanceMetrics {
      let metricName = accessAndUnwrapValue(performanceMetric, "displayName", logger) as? String ?? ""
      let metricUnit = accessAndUnwrapValue(performanceMetric, "unitOfMeasurement", logger) as? String ?? ""
      let metricIdentifier = accessAndUnwrapValue(performanceMetric, "identifier", logger) as? String ?? ""
      let metricMeasurements = accessAndUnwrapValues(performanceMetric, "measurements", logger) as? [NSDictionary] ?? []
      var measurements: [NSNumber] = []
      for metricMeasurement in metricMeasurements {
        if let value = unwrapValue(metricMeasurement) as? NSNumber {
          measurements.append(value)
        }
      }
      let metric: [String: Any] = [
        "name": metricName,
        "unit": metricUnit,
        "identifier": metricIdentifier,
        "measurements": measurements,
      ]
      metrics.append(metric)
    }

    if !JSONSerialization.isValidJSONObject(metrics) {
      logger.log("Not saving performance metrics as they're not valid json")
      return
    }
    guard let json = try? JSONSerialization.data(withJSONObject: metrics, options: .prettyPrinted) else {
      logger.log("Failed to serialize performance metrics")
      return
    }
    do {
      let performanceMetricsDirectory = try ensureSubdirectory("Metrics", insideResultBundle: resultBundlePath)
      let metricFilePath = (performanceMetricsDirectory as NSString).appendingPathComponent("\(testTarget)_\(testClass)_\(testMethod).json")
      try json.write(to: URL(fileURLWithPath: metricFilePath))
    } catch {
      logger.log("Failed to ensure performance metrics directory \(error)")
    }
  }

  private static func buildErrorMessage(_ failureSummaries: NSArray?, logger: FBControlCoreLogger) -> String {
    guard let failureSummaries = failureSummaries as? [NSDictionary] else { return "" }
    var messages: [String] = []
    for failureSummary in failureSummaries {
      if let msg = accessAndUnwrapValue(failureSummary, "message", logger) as? String {
        messages.append(msg)
      }
    }
    return messages.joined(separator: "\n")
  }
}
