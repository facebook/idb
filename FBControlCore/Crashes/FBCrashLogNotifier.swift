/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBCrashLogNotifier)
public class FBCrashLogNotifier: NSObject {

  // MARK: Properties

  @objc public let store: FBCrashLogStore
  private var sinceDate: Date

  // MARK: Initializers

  private init(logger: any FBControlCoreLogger) {
    self.store = FBCrashLogStore.store(forDirectories: FBCrashLogInfo.diagnosticReportsPaths, logger: logger)
    self.sinceDate = Date()
    super.init()
  }

  @objc public class var sharedInstance: FBCrashLogNotifier {
    return _sharedInstance
  }

  nonisolated(unsafe) private static let _sharedInstance: FBCrashLogNotifier = {
    return FBCrashLogNotifier(logger: FBControlCoreGlobalConfiguration.defaultLogger)
  }()

  // MARK: Notifications

  @objc public func startListening(_ onlyNew: Bool) -> Bool {
    sinceDate = onlyNew ? Date() : .distantPast
    return true
  }

  @objc(nextCrashLogForPredicate:)
  public func nextCrashLog(forPredicate predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    _ = startListening(true)

    let queue = DispatchQueue(label: "com.facebook.fbcontrolcore.crashlogfetch")
    let result = FBFuture<AnyObject>.onQueue(
      queue,
      resolveUntil: {
        let crashInfo =
          (FBCrashLogInfo.crashInfo(afterDate: FBCrashLogNotifier.sharedInstance.sinceDate, logger: nil) as NSArray)
          .filtered(using: predicate)
          .first as? FBCrashLogInfo
        guard let crashInfo = crashInfo else {
          return FBControlCoreError.describe("Crash Log Info for \(predicate) could not be obtained").failFuture()
        }
        _ = self.store.ingestCrashLog(atPath: crashInfo.crashPath)
        return FBFuture(result: crashInfo)
      })
    return unsafeBitCast(result, to: FBFuture<FBCrashLogInfo>.self)
  }
}
