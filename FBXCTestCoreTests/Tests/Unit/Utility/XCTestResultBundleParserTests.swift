/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBXCTestCore
import Foundation
import Testing

/// Records what the parser reports, in order, with the detail the shared reporter double drops.
private final class RecordingReporter: NSObject, XCTestReporter, @unchecked Sendable {

  enum Event: Equatable {
    case started(testClass: String, method: String)
    case failed(testClass: String, method: String, messages: [String])
    case finished(testClass: String, method: String, status: FBTestReportStatus, duration: TimeInterval, logs: [String])
    case testPlanFailed(message: String)
  }

  private(set) var events: [Event] = []

  func testCaseDidStart(forTestClass testClass: String, method: String) {
    events.append(.started(testClass: testClass, method: method))
  }

  func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [TestExceptionInfo]) {
    events.append(.failed(testClass: testClass, method: method, messages: exceptions.map(\.message)))
  }

  func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?) {
    events.append(.finished(testClass: testClass, method: method, status: status, duration: duration, logs: logs ?? []))
  }

  func testPlanDidFail(withMessage message: String) {
    events.append(.testPlanFailed(message: message))
  }

  func processWaitingForDebugger(withProcessIdentifier pid: pid_t) {}
  func didBeginExecutingTestPlan() {}
  func didFinishExecutingTestPlan() {}
  func processUnderTestDidExit() {}
  func testSuite(_ testSuite: String, didStartAt startTime: String) {}
  func finished(with summary: TestManagerResultSummary) {}
  func testHadOutput(_ output: String) {}
  func handleExternalEvent(_ event: String) {}
  func printReport() throws {}
  func didCrashDuringTest(_ error: Error) {}
}

@Suite
struct XCTestResultBundleParserTests {

  private let resultBundle: URL

  init() throws {
    resultBundle = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xcresult")
    try FileManager.default.createDirectory(at: resultBundle, withIntermediateDirectories: true)
  }

  private func parse() async throws -> [RecordingReporter.Event] {
    let reporter = RecordingReporter()
    try await XCTestResultBundleParser.parse(resultBundle.path, reporter: reporter, logger: ControlCoreGlobalConfiguration.defaultLogger, extractScreenshots: false)
    return reporter.events
  }

  // MARK: - Legacy TestSummaries.plist

  private func writeTestSummaries(methods: [[String: Any]]) throws {
    let summaries: [String: Any] = [
      "TestableSummaries": [
        [
          "TestName": "MyTests",
          "Tests": [
            ["Subtests": [["Subtests": [["TestIdentifier": "MyTestClass", "Subtests": methods]]]]]
          ],
        ]
      ]
    ]
    (summaries as NSDictionary).write(to: resultBundle.appendingPathComponent("TestSummaries.plist"), atomically: true)
  }

  @Test
  func aPassingLegacyTestIsReportedWithItsInternalActivitiesAsLogs() async throws {
    try writeTestSummaries(methods: [
      [
        "TestIdentifier": "testPasses",
        "TestStatus": "Success",
        "Duration": 0.5,
        "ActivitySummaries": [
          [
            "ActivityType": "com.apple.dt.xctest.activity-type.internal",
            "Title": "Start Test",
            "StartTimeInterval": 100.0,
            "SubActivities": [["Title": "Set Up", "StartTimeInterval": 100.25]],
          ],
          ["ActivityType": "com.apple.dt.xctest.activity-type.userCreated", "Title": "Not logged", "StartTimeInterval": 101.0],
        ],
      ]
    ])

    #expect(
      try await parse() == [
        .started(testClass: "MyTestClass", method: "testPasses"),
        .finished(
          testClass: "MyTestClass", method: "testPasses", status: .passed, duration: 0.5,
          logs: [
            "Test Case '-[MyTests.MyTestClass testPasses]' started.",
            "    t =     0.00s Start Test",
            "    t =     0.25s     Set Up",
            "Test Case '-[MyTests.MyTestClass testPasses]' passed in 0.500 seconds",
          ]),
      ])
  }

  @Test
  func aFailingLegacyTestReportsEveryFailureMessage() async throws {
    try writeTestSummaries(methods: [
      [
        "TestIdentifier": "testFails",
        "TestStatus": "Failure",
        "Duration": 1.25,
        "ActivitySummaries": [],
        "FailureSummaries": [["Message": "first"], ["Message": "second"]],
      ]
    ])

    #expect(
      try await parse() == [
        .started(testClass: "MyTestClass", method: "testFails"),
        .failed(testClass: "MyTestClass", method: "testFails", messages: ["first\nsecond"]),
        .finished(
          testClass: "MyTestClass", method: "testFails", status: .failed, duration: 1.25,
          logs: [
            "Test Case '-[MyTests.MyTestClass testFails]' started.",
            "Test Case '-[MyTests.MyTestClass testFails]' failed in 1.250 seconds",
          ]),
      ])
  }

  @Test
  func aLegacyTestWithAnUnrecognisedStatusFinishesWithAnUnknownStatus() async throws {
    try writeTestSummaries(methods: [
      ["TestIdentifier": "testSkipped", "TestStatus": "Skipped", "Duration": 0.0, "ActivitySummaries": []]
    ])

    let events = try await parse()
    #expect(events.count == 2)
    guard case let .finished(_, _, status, _, logs) = events.last else {
      Issue.record("Expected a finish, got \(events)")
      return
    }
    #expect(status == .unknown)
    #expect(logs.last == "Test Case '-[MyTests.MyTestClass testSkipped]' failed in 0.000 seconds")
  }

  @Test
  func aLegacyTestWithoutADurationFailsTheParse() async throws {
    try writeTestSummaries(methods: [
      ["TestIdentifier": "testNoDuration", "TestStatus": "Success", "ActivitySummaries": []]
    ])

    await #expect {
      _ = try await parse()
    } throws: { error in
      guard case XCTestResultBundleError.missingKey("Duration") = error else { return false }
      return true
    }
  }

  @Test
  func aLegacyTestWhoseStatusIsNotAStringFailsTheParse() async throws {
    try writeTestSummaries(methods: [
      ["TestIdentifier": "testOddStatus", "TestStatus": 1, "Duration": 0.1, "ActivitySummaries": []]
    ])

    await #expect {
      _ = try await parse()
    } throws: { error in
      guard case XCTestResultBundleError.unexpectedType(key: "TestStatus", expected: _) = error else { return false }
      return true
    }
  }

  // MARK: - No Results

  @Test
  func aBundleWithNeitherSummariesNorAFormatVersionFailsTheTestPlan() async throws {
    #expect(try await parse() == [.testPlanFailed(message: "No test results were produced")])
  }
}
