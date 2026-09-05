/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The pause between crash-log scans, matching `AsyncPolling`'s default cadence.
private let CrashLogPollInterval: UInt64 = 100 * NSEC_PER_MSEC

public final class FBCrashLogNotifier {

  // MARK: Properties

  public let store: FBCrashLogStore
  internal var sinceDate: Date

  // MARK: Initializers

  internal init(logger: any FBControlCoreLogger) {
    self.store = FBCrashLogStore.store(forDirectories: FBCrashLogInfo.diagnosticReportsPaths, logger: logger)
    self.sinceDate = Date()
  }

  public class var sharedInstance: FBCrashLogNotifier {
    _sharedInstance
  }

  nonisolated(unsafe) private static let _sharedInstance: FBCrashLogNotifier = {
    FBCrashLogNotifier(logger: FBControlCoreGlobalConfiguration.defaultLogger)
  }()

  // MARK: Notifications

  public func startListening(_ onlyNew: Bool) -> Bool {
    sinceDate = onlyNew ? Date() : .distantPast
    return true
  }

  /// Polls until a crash log matching `predicate` appears; callers impose their own timeouts and task
  /// cancellation stops the poll. Each pass is a synchronous `concurrentPerform` scan that blocks the
  /// calling thread, so the sleep between passes is what keeps a cooperative-pool worker from being
  /// held continuously.
  public func nextCrashLog(forPredicate predicate: NSPredicate) async throws -> FBCrashLogInfo {
    _ = startListening(true)
    while true {
      try Task.checkCancellation()
      let crashInfo =
        (FBCrashLogInfo.crashInfo(afterDate: sinceDate, logger: nil) as NSArray)
        .filtered(using: predicate)
        .first as? FBCrashLogInfo
      if let crashInfo {
        _ = store.ingestCrashLog(atPath: crashInfo.crashPath)
        return crashInfo
      }
      try await Task.sleep(nanoseconds: CrashLogPollInterval)
    }
  }
}
