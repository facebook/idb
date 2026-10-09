/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public final class TestManagerResultSummary: NSObject {

  public let testSuite: String
  public let finishTime: Date
  public let runCount: Int
  public let failureCount: Int
  public let unexpected: Int
  public let testDuration: TimeInterval
  public let totalDuration: TimeInterval

  @objc public static func from(
    testSuite: String,
    finishingAt finishTime: String,
    runCount: NSNumber,
    failures failuresCount: NSNumber,
    unexpected unexpectedFailureCount: NSNumber,
    testDuration: NSNumber,
    totalDuration: NSNumber
  ) -> TestManagerResultSummary {
    TestManagerResultSummary(
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
    super.init()
  }

  public override var description: String {
    "Suite \(testSuite) | Finish Time \(finishTime) | Run Count \(runCount) | Failures \(failureCount) | Unexpected \(unexpected) | Test Duration \(testDuration) | Total Duration \(totalDuration)"
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? TestManagerResultSummary else { return false }
    if other === self { return true }
    return runCount == other.runCount
      && failureCount == other.failureCount
      && unexpected == other.unexpected
      && testDuration == other.testDuration
      && totalDuration == other.totalDuration
      && testSuite == other.testSuite
      && finishTime == other.finishTime
  }

  @objc public static func status(forStatusString statusString: String) -> FBTestReportStatus {
    if statusString == "passed" {
      return .passed
    } else if statusString == "failed" {
      return .failed
    }
    return .unknown
  }

  public static func statusString(for status: FBTestReportStatus) -> String {
    switch status {
    case .passed:
      return "Passed"
    case .failed:
      return "Failed"
    case .unknown:
      return "Unknown"
    @unknown default:
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
