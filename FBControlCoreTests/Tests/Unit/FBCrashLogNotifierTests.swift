/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBCrashLogNotifierTests: XCTestCase {

  // MARK: - startListening

  func testStartListening_WithOnlyNewYES_SetsSinceDateToNow() {
    let notifier = FBCrashLogNotifier(logger: FBControlCoreLoggerDouble())
    notifier.sinceDate = .distantPast

    let before = Date()
    _ = notifier.startListening(true)
    let after = Date()

    XCTAssertGreaterThanOrEqual(
      notifier.sinceDate.timeIntervalSinceReferenceDate,
      before.timeIntervalSinceReferenceDate,
      "sinceDate should be updated to approximately now when onlyNew is YES")
    XCTAssertLessThanOrEqual(
      notifier.sinceDate.timeIntervalSinceReferenceDate,
      after.timeIntervalSinceReferenceDate,
      "sinceDate should not be in the future")
  }

  func testStartListening_WithOnlyNewNO_SetsSinceDateToDistantPast() {
    let notifier = FBCrashLogNotifier(logger: FBControlCoreLoggerDouble())

    _ = notifier.startListening(false)

    XCTAssertEqual(
      notifier.sinceDate, .distantPast,
      "sinceDate should be set to distantPast when onlyNew is NO")
  }

  // MARK: - nextCrashLogForPredicate

  func testNextCrashLogForPredicate_WhenNoMatchingCrashLog_FutureDoesNotResolveWithResult() {
    let notifier = FBCrashLogNotifier(logger: FBControlCoreLoggerDouble())

    let predicate = NSPredicate(value: false)
    let future = notifier.nextCrashLog(forPredicate: predicate)

    XCTAssertThrowsError(
      try future.`await`(withTimeout: 0.2),
      "Future should produce an error (timeout) when no crash log matches")
  }
}
