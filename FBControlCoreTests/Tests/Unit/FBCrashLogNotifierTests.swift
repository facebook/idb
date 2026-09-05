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

  func testNextCrashLogForPredicate_WhenNoMatchingCrashLog_PollDoesNotResolve() async throws {
    let notifier = FBCrashLogNotifier(logger: FBControlCoreLoggerDouble())

    let predicate = NSPredicate(value: false)
    let poll = Task { try await notifier.nextCrashLog(forPredicate: predicate) }

    try await Task.sleep(nanoseconds: 200_000_000)

    // Cancel, or the never-resolving poller outlives the test and keeps re-scanning
    // the host's crash-log directories for the rest of the bundle.
    poll.cancel()
    do {
      _ = try await poll.value
      XCTFail("Poll should not resolve for an always-false predicate")
    } catch {
      XCTAssertTrue(error is CancellationError, "cancelling the poll should surface CancellationError, got \(error)")
    }
  }
}
