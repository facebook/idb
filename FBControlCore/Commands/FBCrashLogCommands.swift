/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBCrashLogCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(crashes:useCache:)
  func crashes(_ predicate: NSPredicate, useCache: Bool) -> FBFuture<NSArray>

  @objc(notifyOfCrash:)
  func notifyOfCrash(_ predicate: NSPredicate) -> FBFuture<FBCrashLogInfo>

  @objc(pruneCrashes:)
  func pruneCrashes(_ predicate: NSPredicate) -> FBFuture<NSArray>

  @objc func crashLogFiles() -> FBFutureContext<FBFileContainerProtocol>
}
