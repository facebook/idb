/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/**
 Bridges the test-host crash-log lookup used by `FBTestBundleConnection` (which remains Objective-C
 for its DTX machinery) onto the Swift `AsyncCrashLogCommands` API, so the connection no longer
 depends on the legacy `FBFuture`-based `FBCrashLogCommands`.

 NOTE: This is temporary scaffolding that exists only because `FBTestBundleConnection` is still
 Objective-C and cannot `await`. It should be removed once that Objective-C class is ported to (or
 replaced by) Swift, at which point the connection can call `AsyncCrashLogCommands` directly.
 */
@objc(FBTestHostCrashLogQuery)
public final class FBTestHostCrashLogQuery: NSObject {

  @objc(notifyOfCrashForProcessIdentifier:target:)
  public static func notifyOfCrash(forProcessIdentifier processIdentifier: pid_t, target: AnyObject) -> FBFuture<FBCrashLogInfo> {
    fbFutureFromAsync {
      guard let asyncTarget = target as? AsyncCrashLogCommands else {
        throw FBControlCoreError.describe("\(target) does not conform to AsyncCrashLogCommands").build()
      }
      let predicate = FBCrashLogInfo.predicateForCrashLogs(withProcessID: processIdentifier)
      return try await asyncTarget.notifyOfCrash(matching: predicate)
    }
  }
}
