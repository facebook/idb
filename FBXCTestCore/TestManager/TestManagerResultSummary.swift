/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The outcome of a test case.
public enum TestReportStatus: UInt {
  case unknown = 0
  case passed = 1
  case failed = 2
}

public final class TestManagerResultSummary: Equatable, CustomStringConvertible {

  public let testSuite: String
  public let finishTime: Date
  public let runCount: Int
  public let failureCount: Int
  public let unexpected: Int
  public let testDuration: TimeInterval
  public let totalDuration: TimeInterval

  /// Parses the values `testmanagerd` reports when a suite finishes.
  public convenience init(
    testSuite: String,
    finishingAt finishTime: String,
    runCount: NSNumber,
    failures failuresCount: NSNumber,
    unexpected unexpectedFailureCount: NSNumber,
    testDuration: NSNumber,
    totalDuration: NSNumber
  ) {
    self.init(
      testSuite: testSuite,
      finishTime: TestManagerResultSummary.dateFormatter.date(from: finishTime) ?? Date(timeIntervalSince1970: 0),
      runCount: runCount.intValue,
      failureCount: failuresCount.intValue,
      unexpected: unexpectedFailureCount.intValue,
      testDuration: testDuration.doubleValue,
      totalDuration: totalDuration.doubleValue
    )
  }

  public init(
    testSuite: String,
    finishTime: Date,
    runCount: Int,
    failureCount: Int,
    unexpected: Int,
    testDuration: TimeInterval,
    totalDuration: TimeInterval
  ) {
    self.testSuite = testSuite
    self.finishTime = finishTime
    self.runCount = runCount
    self.failureCount = failureCount
    self.unexpected = unexpected
    self.testDuration = testDuration
    self.totalDuration = totalDuration
  }

  public var description: String {
    "Suite \(testSuite) | Finish Time \(finishTime) | Run Count \(runCount) | Failures \(failureCount) | Unexpected \(unexpected) | Test Duration \(testDuration) | Total Duration \(totalDuration)"
  }

  public static func == (lhs: TestManagerResultSummary, rhs: TestManagerResultSummary) -> Bool {
    if lhs === rhs { return true }
    return lhs.runCount == rhs.runCount
      && lhs.failureCount == rhs.failureCount
      && lhs.unexpected == rhs.unexpected
      && lhs.testDuration == rhs.testDuration
      && lhs.totalDuration == rhs.totalDuration
      && lhs.testSuite == rhs.testSuite
      && lhs.finishTime == rhs.finishTime
  }

  public static func status(forStatusString statusString: String) -> TestReportStatus {
    if statusString == "passed" {
      return .passed
    } else if statusString == "failed" {
      return .failed
    }
    return .unknown
  }

  public static func statusString(for status: TestReportStatus) -> String {
    switch status {
    case .passed:
      return "Passed"
    case .failed:
      return "Failed"
    case .unknown:
      return "Unknown"
    }
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    formatter.isLenient = true
    formatter.locale = Locale(identifier: "en_US")
    return formatter
  }()
}
