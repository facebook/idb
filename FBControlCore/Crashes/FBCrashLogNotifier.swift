/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The way crash-log polling reports an absent match, as data rather than an assembled string.
public enum FBCrashLogNotifierError: Error, LocalizedError {
  case crashLogUnavailable(predicateDescription: String)

  public var errorDescription: String? {
    switch self {
    case let .crashLogUnavailable(predicateDescription):
      return "Crash Log Info for \(predicateDescription) could not be obtained"
    }
  }
}

public class FBCrashLogNotifier {

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

  public func nextCrashLog(forPredicate predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    _ = startListening(true)

    let queue = DispatchQueue(label: "com.facebook.fbcontrolcore.crashlogfetch")
    let result = FBFuture<AnyObject>.onQueue(
      queue,
      resolveUntil: {
        let crashInfo =
          (FBCrashLogInfo.crashInfo(afterDate: self.sinceDate, logger: nil) as NSArray)
          .filtered(using: predicate)
          .first as? FBCrashLogInfo
        guard let crashInfo else {
          return FBFuture(error: FBCrashLogNotifierError.crashLogUnavailable(predicateDescription: String(describing: predicate)))
        }
        _ = self.store.ingestCrashLog(atPath: crashInfo.crashPath)
        return FBFuture(result: crashInfo)
      })
    return unsafeBitCast(result, to: FBFuture<FBCrashLogInfo>.self)
  }
}
