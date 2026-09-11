/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol CrashLogCommands {

  func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [CrashLogInfo]

  func notifyOfCrash(matching predicate: NSPredicate) async throws -> CrashLogInfo

  func pruneCrashes(matching predicate: NSPredicate) async throws -> [CrashLogInfo]

  func withFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R
}
