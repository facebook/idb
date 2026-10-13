/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct CrashLogNotifierTests {

  // MARK: - startListening

  @Test
  func startListening_WithOnlyNewYES_SetsSinceDateToNow() {
    let notifier = CrashLogNotifier(logger: ControlCoreLoggerDouble())
    notifier.sinceDate = .distantPast

    let before = Date()
    _ = notifier.startListening(true)
    let after = Date()

    #expect(
      notifier.sinceDate.timeIntervalSinceReferenceDate >= before.timeIntervalSinceReferenceDate,
      "sinceDate should be updated to approximately now when onlyNew is YES")
    #expect(
      notifier.sinceDate.timeIntervalSinceReferenceDate <= after.timeIntervalSinceReferenceDate,
      "sinceDate should not be in the future")
  }

  @Test
  func startListening_WithOnlyNewNO_SetsSinceDateToDistantPast() {
    let notifier = CrashLogNotifier(logger: ControlCoreLoggerDouble())

    _ = notifier.startListening(false)

    #expect(
      notifier.sinceDate == .distantPast,
      "sinceDate should be set to distantPast when onlyNew is NO")
  }

  // MARK: - nextCrashLogForPredicate

  @Test
  func nextCrashLogForPredicate_WhenNoMatchingCrashLog_PollDoesNotResolve() async throws {
    let notifier = CrashLogNotifier(logger: ControlCoreLoggerDouble())

    let predicate = CrashLogPredicate.none
    let poll = Task { try await notifier.nextCrashLog(forPredicate: predicate) }

    try await Task.sleep(nanoseconds: 200_000_000)

    // Cancel, or the never-resolving poller outlives the test and keeps re-scanning
    // the host's crash-log directories for the rest of the bundle.
    poll.cancel()
    do {
      _ = try await poll.value
      Issue.record("Poll should not resolve for an always-false predicate")
    } catch {
      #expect(error is CancellationError, "cancelling the poll should surface CancellationError, got \(error)")
    }
  }
}
