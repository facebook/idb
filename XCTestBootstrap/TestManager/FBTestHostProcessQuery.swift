/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/**
 Bridges the host-application process-identifier lookup used by `FBTestBundleConnection` (which
 remains Objective-C for its DTX machinery) onto the Swift `AsyncApplicationCommands` API, so the
 connection no longer depends on the legacy `FBFuture`-based `FBApplicationCommands`.
 */
@objc(FBTestHostProcessQuery)
public final class FBTestHostProcessQuery: NSObject {

  @objc(processIdentifierForBundleID:target:)
  public static func processIdentifier(forBundleID bundleID: String, target: AnyObject) -> FBFuture<NSNumber> {
    fbFutureFromAsync {
      guard let asyncTarget = target as? AsyncApplicationCommands else {
        throw FBControlCoreError.describe("\(target) does not conform to AsyncApplicationCommands").build()
      }
      let processIdentifier = try await asyncTarget.processID(forBundleID: bundleID)
      return NSNumber(value: processIdentifier)
    }
  }
}
