/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let XCTestOperationTimeoutSecs: TimeInterval = 120

// MARK: - Helper functions

private func readFromDict(_ dict: NSDictionary, _ key: String) throws -> Any {
  guard let val = dict[key] else {
    throw XCTestResultBundleError.missingKey(key)
  }
  return val
}

private func read<T>(_ dict: NSDictionary, _ key: String, as type: T.Type) throws -> T {
  guard let val = try readFromDict(dict, key) as? T else {
    throw XCTestResultBundleError.unexpectedType(key: key, expected: String(describing: type))
  }
  return val
}

private func readNumberFromDict(_ dict: NSDictionary, _ key: String) throws -> NSNumber {
  try read(dict, key, as: NSNumber.self)
}

private func readDoubleFromDict(_ dict: NSDictionary, _ key: String) throws -> Double {
  try readNumberFromDict(dict, key).doubleValue
}

private func readStringFromDict(_ dict: NSDictionary, _ key: String) throws -> String {
  try read(dict, key, as: String.self)
}

private func readDictionaryFromDict(_ dict: NSDictionary, _ key: String) throws -> NSDictionary {
  try read(dict, key, as: NSDictionary.self)
}

private func readDictionaryArrayFromDict(_ dict: NSDictionary, _ key: String) throws -> [NSDictionary] {
  try read(dict, key, as: [NSDictionary].self)
}

private func unwrapValues(_ wrapped: NSDictionary) -> NSArray? {
  wrapped["_values"] as? NSArray
}

private func unwrapValue(_ wrapped: NSDictionary) -> Any? {
  wrapped["_value"]
}

private func accessAndUnwrapValues(_ dict: NSDictionary, _ key: String, _ logger: ControlCoreLogger) -> NSArray? {
  guard let wrapped = dict[key] as? NSDictionary else {
    logger.log("\(key) does not exist inside \(CollectionInformation.oneLineDescription(from: dict.allKeys))")
    return nil
  }
  let unwrapped = unwrapValues(wrapped)
  if unwrapped == nil {
    logger.log("Failed to unwrap values for \(key) from \(CollectionInformation.oneLineDescription(from: wrapped.allKeys))")
  }
  return unwrapped
}

private func accessAndUnwrapValue(_ dict: NSDictionary, _ key: String, _ logger: ControlCoreLogger) -> Any? {
  guard let wrapped = dict[key] as? NSDictionary else {
    logger.log("\(key) does not exist inside \(CollectionInformation.oneLineDescription(from: dict.allKeys))")
    return nil
  }
  let unwrapped = unwrapValue(wrapped)
  if unwrapped == nil {
    logger.log("Failed to unwrap value for \(key) from \(CollectionInformation.oneLineDescription(from: wrapped.allKeys))")
  }
  return unwrapped
}

private let FBXCTestResultBundleParser_dateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
  return formatter
}()

private func dateFromString(_ date: String) -> Date? {
  return FBXCTestResultBundleParser_dateFormatter.date(from: date)
}

enum XCTestResultBundleError: Error {
  case noActions
  case notADirectory(path: String)
  case missingKey(String)
  case unexpectedType(key: String, expected: String)
}

extension XCTestResultBundleError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .noActions:
      return "Test result bundle root record does not contain any actions"
    case let .notADirectory(path):
      return "\(path) is not a directory"
    case let .missingKey(key):
      return "Test result bundle has no \(key)"
    case let .unexpectedType(key, expected):
      return "Test result bundle's \(key) is not a \(expected)"
    }
  }
}

final class XCTestResultBundleParser {

  // MARK: - Public

  public static func parse(_ resultBundlePath: String, reporter: XCTestReporter, logger: ControlCoreLogger, extractScreenshots: Bool) async throws {
    logger.log("Parsing the result bundle \(resultBundlePath)")

    let testSummariesPath = (resultBundlePath as NSString).appendingPathComponent("TestSummaries.plist")
    let results = NSDictionary(contentsOfFile: testSummariesPath)
    let resultBundleInfoPath = (resultBundlePath as NSString).appendingPathComponent("Info.plist")
    let bundleInfo = NSDictionary(contentsOfFile: resultBundleInfoPath)
    let bundleFormatVersion = bundleInfo?["version"]

    if let results {
      try reportResultsLegacy(results, reporter: reporter)
      logger.log("ResultBundlePath: \(resultBundlePath)")
      return
    }
    guard let bundleFormatVersion = bundleFormatVersion as? NSDictionary else {
      reporter.testPlanDidFail?(withMessage: "No test results were produced")
      return
    }
    let majorVersion = try readNumberFromDict(bundleFormatVersion, "major")
    let minorVersion = try readNumberFromDict(bundleFormatVersion, "minor")
    logger.log("Test result bundle format version: \(majorVersion).\(minorVersion)")

    let record = try await XCTestResultToolOperation.getJSON(from: resultBundlePath, forId: nil, logger: logger)
    guard let actions = record["actions"] as? NSDictionary else {
      throw XCTestResultBundleError.noActions
    }
    for bundleObjectId in try parseActions(actions, logger: logger) {
      let xcresults = try await XCTestResultToolOperation.getJSON(from: resultBundlePath, forId: bundleObjectId, logger: logger)
      logger.log("Parsing summaries for id \(bundleObjectId)")
      let summaries = accessAndUnwrapValues(xcresults, "summaries", logger)
      await reportSummaries(summaries, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
      logger.log("Done parsing summaries for id \(bundleObjectId)")
    }
  }

  // MARK: - Private: Legacy XCTest Result Parsing

  private static func reportResultsLegacy(_ results: NSDictionary, reporter: XCTestReporter) throws {
    let testTargets = results["TestableSummaries"] as? [NSDictionary]
    try reportTargetTestsLegacy(testTargets, reporter: reporter)
  }

  private static func reportTargetTestsLegacy(_ targetTests: [NSDictionary]?, reporter: XCTestReporter) throws {
    guard let targetTests else { return }
    for targetTest in targetTests {
      try reportTargetTestLegacy(targetTest, reporter: reporter)
    }
  }

  private static func reportTargetTestLegacy(_ targetTest: NSDictionary, reporter: XCTestReporter) throws {
    let testBundleName = try readStringFromDict(targetTest, "TestName")
    let selectedTests = targetTest["Tests"] as? [NSDictionary]
    try reportSelectedTestsLegacy(selectedTests, testBundleName: testBundleName, reporter: reporter)
  }

  private static func reportSelectedTestsLegacy(_ selectedTests: [NSDictionary]?, testBundleName: String, reporter: XCTestReporter) throws {
    guard let selectedTests else { return }
    for selectedTest in selectedTests {
      try reportSelectedTestLegacy(selectedTest, testBundleName: testBundleName, reporter: reporter)
    }
  }

  private static func reportSelectedTestLegacy(_ selectedTest: NSDictionary, testBundleName: String, reporter: XCTestReporter) throws {
    let testTargetXctests = selectedTest["Subtests"] as? [NSDictionary]
    try reportTestTargetXctestsLegacy(testTargetXctests, testBundleName: testBundleName, reporter: reporter)
  }

  private static func reportTestTargetXctestsLegacy(_ testTargetXctests: [NSDictionary]?, testBundleName: String, reporter: XCTestReporter) throws {
    guard let testTargetXctests else { return }
    for testTargetXctest in testTargetXctests {
      try reportTestTargetXctestLegacy(testTargetXctest, testBundleName: testBundleName, reporter: reporter)
    }
  }

  private static func reportTestTargetXctestLegacy(_ testTargetXctest: NSDictionary, testBundleName: String, reporter: XCTestReporter) throws {
    let testClasses = testTargetXctest["Subtests"] as? [NSDictionary]
    try reportTestClassesLegacy(testClasses, testBundleName: testBundleName, reporter: reporter)
  }

  private static func reportTestClassesLegacy(_ testClasses: [NSDictionary]?, testBundleName: String, reporter: XCTestReporter) throws {
    guard let testClasses else { return }
    for testClass in testClasses {
      try reportTestClassLegacy(testClass, testBundleName: testBundleName, reporter: reporter)
    }
  }

  private static func reportTestClassLegacy(_ testClass: NSDictionary, testBundleName: String, reporter: XCTestReporter) throws {
    let testClassName = try readStringFromDict(testClass, "TestIdentifier")
    let testMethods = testClass["Subtests"] as? [NSDictionary]
    try reportTestMethodsLegacy(testMethods, testBundleName: testBundleName, testClassName: testClassName, reporter: reporter)
  }

  private static func reportTestMethodsLegacy(_ testMethods: [NSDictionary]?, testBundleName: String, testClassName: String, reporter: XCTestReporter) throws {
    guard let testMethods else { return }
    for testMethod in testMethods {
      try reportTestMethodLegacy(testMethod, testBundleName: testBundleName, testClassName: testClassName, reporter: reporter)
    }
  }

  private static func reportTestMethodLegacy(_ testMethod: NSDictionary, testBundleName: String, testClassName: String, reporter: XCTestReporter) throws {
    let testStatus = try readStringFromDict(testMethod, "TestStatus")
    let testMethodName = try readStringFromDict(testMethod, "TestIdentifier")
    let duration = try readNumberFromDict(testMethod, "Duration")

    var status = FBTestReportStatus.unknown
    if testStatus == "Success" {
      status = .passed
    }
    if testStatus == "Failure" {
      status = .failed
    }

    let activitySummaries = try readDictionaryArrayFromDict(testMethod, "ActivitySummaries")
    let logs = try buildTestLogLegacy(activitySummaries, testBundleName: testBundleName, testClassName: testClassName, testMethodName: testMethodName, testPassed: status == .passed, duration: duration.doubleValue)

    reporter.testCaseDidStart(forTestClass: testClassName, method: testMethodName)
    if status == .failed {
      let failureSummaries = try readDictionaryArrayFromDict(testMethod, "FailureSummaries")
      reporter.testCaseDidFail(
        forTestClass: testClassName, method: testMethodName,
        exceptions: [
          TestExceptionInfo(message: try buildErrorMessageLegacy(failureSummaries))
        ])
    }
    reporter.testCaseDidFinish(forTestClass: testClassName, method: testMethodName, with: status, duration: duration.doubleValue, logs: logs)
  }

  private static func buildTestLogLegacy(_ activitySummaries: [NSDictionary], testBundleName: String, testClassName: String, testMethodName: String, testPassed: Bool, duration: Double) throws -> [String] {
    var logs: [String] = []
    let testCaseFullName = "-[\(testBundleName).\(testClassName) \(testMethodName)]"
    logs.append("Test Case '\(testCaseFullName)' started.")

    var testStartTimeInterval: Double = 0
    var startTimeSet = false
    for activitySummary in activitySummaries {
      if !startTimeSet {
        testStartTimeInterval = try readDoubleFromDict(activitySummary, "StartTimeInterval")
        startTimeSet = true
      }

      let activityType = try readStringFromDict(activitySummary, "ActivityType")
      if activityType == "com.apple.dt.xctest.activity-type.internal" {
        try addTestLogsFromLegacyActivitySummary(activitySummary, logs: &logs, testStartTimeInterval: testStartTimeInterval, indent: 0)
      }
    }

    logs.append("Test Case '\(testCaseFullName)' \(testPassed ? "passed" : "failed") in \(String(format: "%.3f", duration)) seconds")
    return logs
  }

  private static func addTestLogsFromLegacyActivitySummary(_ activitySummary: NSDictionary, logs: inout [String], testStartTimeInterval: Double, indent: UInt) throws {
    let message = try readStringFromDict(activitySummary, "Title")
    let startTimeInterval = try readDoubleFromDict(activitySummary, "StartTimeInterval")
    let elapsed = startTimeInterval - testStartTimeInterval
    let indentString = "".padding(toLength: 1 + Int(indent) * 4, withPad: " ", startingAt: 0)
    let log = String(format: "    t = %8.2fs%@%@", elapsed, indentString, message)
    logs.append(log)

    guard let subActivities = activitySummary["SubActivities"] as? [NSDictionary] else {
      return
    }
    for subActivity in subActivities {
      try addTestLogsFromLegacyActivitySummary(subActivity, logs: &logs, testStartTimeInterval: testStartTimeInterval, indent: indent + 1)
    }
  }

  private static func buildErrorMessageLegacy(_ failureSummaries: [NSDictionary]) throws -> String {
    var messages: [String] = []
    for failureSummary in failureSummaries {
      messages.append(try readStringFromDict(failureSummary, "Message"))
    }
    return messages.joined(separator: "\n")
  }

  // MARK: - Private: Xcode 11+ XCTest Result Parsing

  private static func parseActions(_ actions: NSDictionary, logger: ControlCoreLogger) throws -> [String] {
    guard let actionValues = unwrapValues(actions) as? [NSDictionary] else {
      throw XCTestResultBundleError.unexpectedType(key: "actions", expected: "array of actions")
    }
    var ids: [String] = []
    for action in actionValues {
      ids.append(try parseAction(action, logger: logger))
    }
    return ids
  }

  private static func parseAction(_ action: NSDictionary, logger: ControlCoreLogger) throws -> String {
    try parseActionResult(try readDictionaryFromDict(action, "actionResult"), logger: logger)
  }

  private static func parseActionResult(_ actionResult: NSDictionary, logger: ControlCoreLogger) throws -> String {
    try parseTestsRef(try readDictionaryFromDict(actionResult, "testsRef"), logger: logger)
  }

  private static func parseTestsRef(_ testsRef: NSDictionary, logger: ControlCoreLogger) throws -> String {
    guard let id = accessAndUnwrapValue(testsRef, "id", logger) as? String else {
      throw XCTestResultBundleError.unexpectedType(key: "testsRef.id", expected: String(describing: String.self))
    }
    return id
  }

  private static func reportSummaries(_ summaries: NSArray?, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    guard let summaries = summaries as? [NSDictionary] else { return }
    for summary in summaries {
      await reportResults(summary, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportResults(_ results: NSDictionary, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    let testTargets = accessAndUnwrapValues(results, "testableSummaries", logger)
    await reportTargetTests(testTargets, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
  }

  private static func reportTargetTests(_ targetTests: NSArray?, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    guard let targetTests = targetTests as? [NSDictionary] else { return }
    for targetTest in targetTests {
      await reportTargetTest(targetTest, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportTargetTest(_ targetTest: NSDictionary, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    let testBundleName = accessAndUnwrapValue(targetTest, "targetName", logger) as? String ?? ""
    let selectedTests = accessAndUnwrapValues(targetTest, "tests", logger)
    if selectedTests != nil {
      await reportSelectedTests(selectedTests, testBundleName: testBundleName, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    } else {
      logger.log("Test failed and no test results found in the bundle")
      let failureSummaries = accessAndUnwrapValues(targetTest, "failureSummaries", logger)
      reporter.testCaseDidFail(
        forTestClass: "", method: "",
        exceptions: [
          TestExceptionInfo(message: buildErrorMessage(failureSummaries, logger: logger))
        ])
    }
  }

  private static func reportSelectedTests(_ selectedTests: NSArray?, testBundleName: String, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    guard let selectedTests = selectedTests as? [NSDictionary] else { return }
    for selectedTest in selectedTests {
      await reportSelectedTest(selectedTest, testBundleName: testBundleName, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportSelectedTest(_ selectedTest: NSDictionary, testBundleName: String, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    let testTargetXctests = accessAndUnwrapValues(selectedTest, "subtests", logger)
    if testTargetXctests != nil {
      await reportTestTargetXctests(testTargetXctests, testBundleName: testBundleName, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    } else {
      logger.log("Test failed and no target test results found in the bundle")
      reporter.testCaseDidFail(
        forTestClass: "", method: "",
        exceptions: [
          TestExceptionInfo(message: "")
        ])
    }
  }

  private static func reportTestTargetXctests(_ testTargetXctests: NSArray?, testBundleName: String, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    guard let testTargetXctests = testTargetXctests as? [NSDictionary] else { return }
    for testTargetXctest in testTargetXctests {
      await reportTestTargetXctest(testTargetXctest, testBundleName: testBundleName, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportTestTargetXctest(_ testTargetXctest: NSDictionary, testBundleName: String, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    let testClasses = accessAndUnwrapValues(testTargetXctest, "subtests", logger)
    if testClasses != nil {
      await reportTestClasses(testClasses, testBundleName: testBundleName, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    } else {
      logger.log("Test failed and no test class results found in the bundle")
      reporter.testCaseDidFail(
        forTestClass: "", method: "",
        exceptions: [
          TestExceptionInfo(message: "")
        ])
    }
  }

  private static func reportTestClasses(_ testClasses: NSArray?, testBundleName: String, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    guard let testClasses = testClasses as? [NSDictionary] else { return }
    for testClass in testClasses {
      await reportTestClass(testClass, testBundleName: testBundleName, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportTestClass(_ testClass: NSDictionary, testBundleName: String, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    let testClassName = accessAndUnwrapValue(testClass, "identifier", logger) as? String ?? ""
    let testMethods = accessAndUnwrapValues(testClass, "subtests", logger)
    if testMethods != nil {
      await reportTestMethods(testMethods, testBundleName: testBundleName, testClassName: testClassName, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    } else {
      logger.log("Test failed for \(testClassName) and no test method results found")
      reporter.testCaseDidFail(
        forTestClass: "", method: "",
        exceptions: [
          TestExceptionInfo(message: "")
        ])
    }
  }

  private static func reportTestMethods(_ testMethods: NSArray?, testBundleName: String, testClassName: String, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
    guard let testMethods = testMethods as? [NSDictionary] else { return }
    for testMethod in testMethods {
      await reportTestMethod(testMethod, testBundleName: testBundleName, testClassName: testClassName, reporter: reporter, resultBundlePath: resultBundlePath, logger: logger, extractScreenshots: extractScreenshots)
    }
  }

  private static func reportTestMethod(_ testMethod: NSDictionary, testBundleName: String, testClassName: String, reporter: XCTestReporter, resultBundlePath: String, logger: ControlCoreLogger, extractScreenshots: Bool) async {
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
      // A tool failure abandons this method's summary: the case has started
      // and never finishes.
      guard let actionTestSummary = try? await XCTestResultToolOperation.getJSON(from: resultBundlePath, forId: summaryRefId, logger: logger, timeout: XCTestOperationTimeoutSecs) else {
        return
      }
      if status == .failed {
        let failureSummaries = accessAndUnwrapValues(actionTestSummary, "failureSummaries", logger)
        reporter.testCaseDidFail(
          forTestClass: testClassName, method: testMethodIdentifier,
          exceptions: [
            TestExceptionInfo(message: buildErrorMessage(failureSummaries, logger: logger))
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
        await extractScreenshotsFromActivities(activitySummaries, resultBundlePath: resultBundlePath, logger: logger)
      }

      let logs = buildTestLog(accessAndUnwrapValues(actionTestSummary, "activitySummaries", logger) as? [NSDictionary], testBundleName: testBundleName, testClassName: testClassName, testMethodName: testMethodIdentifier, testPassed: status == .passed, duration: duration.doubleValue, logger: logger)
      reporter.testCaseDidFinish(forTestClass: testClassName, method: testMethodIdentifier, with: status, duration: duration.doubleValue, logs: logs)
    }
  }

  private static func buildTestLog(_ activitySummaries: [NSDictionary]?, testBundleName: String, testClassName: String, testMethodName: String, testPassed: Bool, duration: Double, logger: ControlCoreLogger) -> [String] {
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

  private static func addTestLogsFromActivitySummary(_ activitySummary: NSDictionary, logs: inout [String], testStartTimeInterval: Double, indent: UInt, logger: ControlCoreLogger) {
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

  private static func extractScreenshotsFromActivities(_ activities: [NSDictionary], resultBundlePath: String, logger: ControlCoreLogger) async {
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
          await extractScreenshotsFromAttachments(attachments, to: screenshotsPath, resultBundlePath: resultBundlePath, logger: logger)
        }
      }
      if activity["subactivities"] != nil {
        if let subactivities = accessAndUnwrapValues(activity, "subactivities", logger) as? [NSDictionary] {
          await extractScreenshotsFromActivities(subactivities, resultBundlePath: resultBundlePath, logger: logger)
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
        throw XCTestResultBundleError.notADirectory(path: subdirectoryFullPath)
      }
    } else {
      try fileManager.createDirectory(atPath: subdirectoryFullPath, withIntermediateDirectories: false, attributes: nil)
    }
    return subdirectoryFullPath
  }

  private static func extractScreenshotsFromAttachments(_ attachments: [NSDictionary], to destination: String, resultBundlePath: String, logger: ControlCoreLogger) async {
    for attachment in attachments {
      guard let filename = accessAndUnwrapValue(attachment, "filename", logger) as? String else { continue }
      guard filename.hasPrefix("Screenshot_"),
        let payloadRef = attachment["payloadRef"] as? NSDictionary,
        let screenshotId = accessAndUnwrapValue(payloadRef, "id", logger) as? String,
        let screenshotType = accessAndUnwrapValue(attachment, "uniformTypeIdentifier", logger) as? String
      else { continue }
      let timestamp = accessAndUnwrapValue(attachment, "timestamp", logger) as? String ?? ""
      let jpgFilename = (filename as NSString).deletingPathExtension.appending(".jpg")
      let exportPath = (destination as NSString).appendingPathComponent("\(timestamp)_\(jpgFilename)")
      _ = try? await XCTestResultToolOperation.exportJPEG(from: resultBundlePath, to: exportPath, forId: screenshotId, type: screenshotType, logger: logger, timeout: XCTestOperationTimeoutSecs)
    }
  }

  private static func savePerformanceMetrics(_ performanceMetrics: [NSDictionary], toTestResultBundle resultBundlePath: String, forTestTarget testTarget: String, testClass: String, testMethod: String, logger: ControlCoreLogger) {
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

  private static func buildErrorMessage(_ failureSummaries: NSArray?, logger: ControlCoreLogger) -> String {
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
