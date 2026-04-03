/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public final class FBTestManagerResultSummary: NSObject {

  @objc public let testSuite: String
  @objc public let finishTime: Date
  @objc public let runCount: Int
  @objc public let failureCount: Int
  @objc public let unexpected: Int
  @objc public let testDuration: TimeInterval
  @objc public let totalDuration: TimeInterval

  @objc public class func from(
    testSuite: String,
    finishingAt finishTime: String,
    runCount: NSNumber,
    failures failuresCount: NSNumber,
    unexpected unexpectedFailureCount: NSNumber,
    testDuration: NSNumber,
    totalDuration: NSNumber
  ) -> FBTestManagerResultSummary {
    return FBTestManagerResultSummary(
      testSuite: testSuite,
      finishTime: FBTestManagerResultSummary.dateFormatter.date(from: finishTime)!,
      runCount: runCount.intValue,
      failureCount: failuresCount.intValue,
      unexpected: unexpectedFailureCount.intValue,
      testDuration: testDuration.doubleValue,
      totalDuration: totalDuration.doubleValue
    )
  }

  @objc public init(
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
    return "Suite \(testSuite) | Finish Time \(finishTime) | Run Count \(runCount) | Failures \(failureCount) | Unexpected \(unexpected) | Test Duration \(testDuration) | Total Duration \(totalDuration)"
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBTestManagerResultSummary else { return false }
    if other === self { return true }
    return runCount == other.runCount
      && failureCount == other.failureCount
      && unexpected == other.unexpected
      && testDuration == other.testDuration
      && totalDuration == other.totalDuration
      && testSuite == other.testSuite
      && finishTime == other.finishTime
  }

  @objc public class func status(forStatusString statusString: String) -> FBTestReportStatus {
    if statusString == "passed" {
      return .passed
    } else if statusString == "failed" {
      return .failed
    }
    return .unknown
  }

  @objc public class func statusString(for status: FBTestReportStatus) -> String {
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
