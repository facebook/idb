/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBCrashLogCommands`.
public protocol AsyncCrashLogCommands: AnyObject {

  func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo]

  func notifyOfCrash(matching predicate: NSPredicate) async throws -> FBCrashLogInfo

  func pruneCrashes(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo]

  func withCrashLogFiles<R>(body: (any FBFileContainerProtocol) async throws -> R) async throws -> R
}
