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

/// Serves xcresult records from memory, keyed by id with `nil` for the root, and records exports.
private final class FakeXCResult: XCResultReading, @unchecked Sendable {

  var root: [String: Any] = [:]
  var records: [String: [String: Any]] = [:]
  private(set) var exports: [(destination: String, id: String, type: String)] = []

  struct Missing: Error {}

  func record(forId bundleObjectId: String?, timeout: TimeInterval?) async throws -> ResultRecord {
    guard let bundleObjectId else {
      return ResultRecord(root)
    }
    guard let record = records[bundleObjectId] else {
      throw Missing()
    }
    return ResultRecord(record)
  }

  func exportJPEG(to destination: String, forId bundleObjectId: String, type encodeType: String, timeout: TimeInterval?) async throws {
    exports.append((destination, bundleObjectId, encodeType))
  }
}

/// xcresulttool's JSON wraps every scalar as `{"_value": "…"}`, with the value as a string, and
/// every array as `{"_values": […]}`.
private func value(_ value: String) -> [String: Any] {
  ["_value": value]
}

private func values(_ values: [[String: Any]]) -> [String: Any] {
  ["_values": values]
}

@Suite
struct XCTestResultBundleParserTests {

  private let resultBundle: URL

  init() throws {
    resultBundle = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xcresult")
    try FileManager.default.createDirectory(at: resultBundle, withIntermediateDirectories: true)
  }

  private func parse(xcresult: FakeXCResult = FakeXCResult(), extractScreenshots: Bool = false) async throws -> [RecordingReporter.Event] {
    let reporter = RecordingReporter()
    try await XCTestResultBundleParser.parse(resultBundle.path, reporter: reporter, logger: ControlCoreGlobalConfiguration.defaultLogger, extractScreenshots: extractScreenshots, tool: xcresult)
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
    #expect(logs.last == "Test Case '-[MyTests.MyTestClass testSkipped]' skipped in 0.000 seconds")
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

  // MARK: - xcresult

  private func xcresult(methods: [[String: Any]], summaries: [String: [String: Any]] = [:]) throws -> FakeXCResult {
    (["version": ["major": 3, "minor": 39]] as NSDictionary).write(to: resultBundle.appendingPathComponent("Info.plist"), atomically: true)
    let xcresult = FakeXCResult()
    xcresult.root = ["actions": values([["actionResult": ["testsRef": ["id": value("TESTS")]]]])]
    xcresult.records["TESTS"] = [
      "summaries": values([
        [
          "testableSummaries": values([
            [
              "targetName": value("MyTests"),
              "tests": values([["subtests": values([["subtests": values([["identifier": value("MyTestClass"), "subtests": values(methods)]])]])]]),
            ]
          ])
        ]
      ])
    ]
    xcresult.records.merge(summaries) { $1 }
    return xcresult
  }

  private func method(_ identifier: String, status: String, duration: String = "0.5", summaryRef: String? = nil) -> [String: Any] {
    var method: [String: Any] = [
      "identifier": value(identifier),
      "name": value("\(identifier)()"),
      "testStatus": value(status),
      "duration": value(duration),
    ]
    if let summaryRef {
      method["summaryRef"] = ["id": value(summaryRef)]
    }
    return method
  }

  private let startTest: [String: Any] = [
    "activityType": value("com.apple.dt.xctest.activity-type.internal"),
    "title": value("Start Test"),
    "start": value("2023-01-01T10:00:00.000+0000"),
    "subactivities": values([["title": value("Set Up"), "start": value("2023-01-01T10:00:00.250+0000")]]),
  ]

  @Test
  func aPassingTestIsReportedWithItsInternalActivitiesAsLogs() async throws {
    let xcresult = try xcresult(
      methods: [method("testPasses", status: "Success", summaryRef: "SUMMARY")],
      summaries: ["SUMMARY": ["activitySummaries": values([startTest])]])

    #expect(
      try await parse(xcresult: xcresult) == [
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
  func aFailingTestReportsItsFailureMessages() async throws {
    let xcresult = try xcresult(
      methods: [method("testFails", status: "Failure", summaryRef: "SUMMARY")],
      summaries: ["SUMMARY": ["failureSummaries": values([["message": value("first")], ["message": value("second")]])]])

    let events = try await parse(xcresult: xcresult)
    #expect(events.count == 3)
    #expect(events[1] == .failed(testClass: "MyTestClass", method: "testFails", messages: ["first\nsecond"]))
  }

  @Test
  func aSkippedTestFinishesWithAnUnknownStatus() async throws {
    let xcresult = try xcresult(methods: [method("testSkipped", status: "Skipped", duration: "0", summaryRef: "SUMMARY")], summaries: ["SUMMARY": [:]])

    let events = try await parse(xcresult: xcresult)
    guard case let .finished(_, _, status, _, logs) = events.last else {
      Issue.record("Expected a finish, got \(events)")
      return
    }
    #expect(status == .unknown)
    #expect(logs.last == "Test Case '-[MyTests.MyTestClass testSkipped]' skipped in 0.000 seconds")
  }

  @Test
  func aTestWithoutASummaryFinishesWithItsOwnStatusAndDuration() async throws {
    let xcresult = try xcresult(methods: [method("testNoSummary", status: "Success")])

    #expect(
      try await parse(xcresult: xcresult) == [
        .started(testClass: "MyTestClass", method: "testNoSummary"),
        .finished(
          testClass: "MyTestClass", method: "testNoSummary", status: .passed, duration: 0.5,
          logs: [
            "Test Case '-[MyTests.MyTestClass testNoSummary]' started.",
            "Test Case '-[MyTests.MyTestClass testNoSummary]' passed in 0.500 seconds",
          ]),
      ])
  }

  @Test
  func aTestWhoseSummaryCannotBeReadFinishesWithItsOwnStatusAndDuration() async throws {
    let xcresult = try xcresult(methods: [method("testUnreadable", status: "Success", summaryRef: "MISSING")])

    #expect(
      try await parse(xcresult: xcresult) == [
        .started(testClass: "MyTestClass", method: "testUnreadable"),
        .finished(
          testClass: "MyTestClass", method: "testUnreadable", status: .passed, duration: 0.5,
          logs: [
            "Test Case '-[MyTests.MyTestClass testUnreadable]' started.",
            "Test Case '-[MyTests.MyTestClass testUnreadable]' passed in 0.500 seconds",
          ]),
      ])
  }

  @Test
  func aTargetWithoutTestsReportsItsFailuresAgainstNoTest() async throws {
    let xcresult = try xcresult(methods: [])
    xcresult.records["TESTS"] = [
      "summaries": values([
        ["testableSummaries": values([["targetName": value("MyTests"), "failureSummaries": values([["message": value("launch failed")]])]])]
      ])
    ]

    #expect(try await parse(xcresult: xcresult) == [.failed(testClass: "", method: "", messages: ["launch failed"])])
  }

  private func xcresult(tests: [[String: Any]]) throws -> FakeXCResult {
    let xcresult = try xcresult(methods: [])
    xcresult.records["TESTS"] = [
      "summaries": values([["testableSummaries": values([["targetName": value("MyTests"), "tests": values(tests)]])]])
    ]
    return xcresult
  }

  @Test
  func aTestGroupWithoutSubtestsReportsAFailure() async throws {
    let xcresult = try xcresult(tests: [[:]])

    // BUG: the failure names no test and says nothing about what was missing — flipped in the
    // following commit.
    #expect(try await parse(xcresult: xcresult) == [.failed(testClass: "", method: "", messages: [""])])
  }

  @Test
  func aTestBundleWithoutClassesReportsAFailure() async throws {
    let xcresult = try xcresult(tests: [["subtests": values([[:]])]])

    // BUG: as above — flipped in the following commit.
    #expect(try await parse(xcresult: xcresult) == [.failed(testClass: "", method: "", messages: [""])])
  }

  @Test
  func aTestClassWithoutMethodsReportsAFailure() async throws {
    let xcresult = try xcresult(tests: [["subtests": values([["subtests": values([["identifier": value("MyTestClass")]])]])]])

    // BUG: as above, though the class is known — flipped in the following commit.
    #expect(try await parse(xcresult: xcresult) == [.failed(testClass: "", method: "", messages: [""])])
  }

  @Test
  func performanceMetricsAreSavedBesideTheBundle() async throws {
    let xcresult = try xcresult(
      methods: [method("testMeasures", status: "Success", summaryRef: "SUMMARY")],
      summaries: [
        "SUMMARY": [
          "performanceMetrics": values([
            [
              "displayName": value("Clock Monotonic Time"),
              "unitOfMeasurement": value("s"),
              "identifier": value("com.apple.dt.XCTMetric_Clock.time.monotonic"),
              "measurements": values([value("0.1"), value("0.2")]),
            ]
          ])
        ]
      ])

    _ = try await parse(xcresult: xcresult)

    let metricsFile = resultBundle.appendingPathComponent("Metrics/MyTests_MyTestClass_testMeasures.json")
    let metrics = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: metricsFile)) as? [[String: Any]])
    #expect(metrics.count == 1)
    #expect(metrics[0]["name"] as? String == "Clock Monotonic Time")
    #expect(metrics[0]["unit"] as? String == "s")
    #expect(metrics[0]["identifier"] as? String == "com.apple.dt.XCTMetric_Clock.time.monotonic")
    #expect((metrics[0]["measurements"] as? [Double]) == [0.1, 0.2])
  }

  @Test
  func screenshotsAreExportedOnlyWhenAsked() async throws {
    let screenshotActivity: [String: Any] = [
      "activityType": value("com.apple.dt.xctest.activity-type.userCreated"),
      "title": value("Take Screenshot"),
      "start": value("2023-01-01T10:00:00.000+0000"),
      "attachments": values([
        [
          "filename": value("Screenshot_1.heic"),
          "payloadRef": ["id": value("PAYLOAD")],
          "uniformTypeIdentifier": value("public.heic"),
          "timestamp": value("TIME"),
        ],
        ["filename": value("log.txt"), "payloadRef": ["id": value("LOG")], "uniformTypeIdentifier": value("public.plain-text")],
      ]),
    ]
    let summaries = ["SUMMARY": ["activitySummaries": values([screenshotActivity])]]

    let notAsked = try xcresult(methods: [method("testScreens", status: "Success", summaryRef: "SUMMARY")], summaries: summaries)
    _ = try await parse(xcresult: notAsked, extractScreenshots: false)
    #expect(notAsked.exports.isEmpty)

    let asked = try xcresult(methods: [method("testScreens", status: "Success", summaryRef: "SUMMARY")], summaries: summaries)
    _ = try await parse(xcresult: asked, extractScreenshots: true)
    #expect(asked.exports.map(\.id) == ["PAYLOAD"])
    #expect(asked.exports.first?.type == "public.heic")
    #expect(asked.exports.first?.destination == resultBundle.appendingPathComponent("Attachments/TIME_Screenshot_1.jpg").path)
  }

  @Test
  func aRootRecordWithoutActionsFailsTheParse() async throws {
    let xcresult = try xcresult(methods: [])
    xcresult.root = [:]

    await #expect {
      _ = try await parse(xcresult: xcresult)
    } throws: { error in
      guard case XCTestResultBundleError.noActions = error else { return false }
      return true
    }
  }

  // MARK: - No Results

  @Test
  func aBundleWithNeitherSummariesNorAFormatVersionFailsTheTestPlan() async throws {
    #expect(try await parse() == [.testPlanFailed(message: "No test results were produced")])
  }
}
