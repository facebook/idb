/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol CrashLogCommands {

  func crashes(matching predicate: CrashLogPredicate, useCache: Bool) async throws -> [CrashLogInfo]

  func notifyOfCrash(matching predicate: CrashLogPredicate) async throws -> CrashLogInfo

  func prune(matching predicate: CrashLogPredicate) async throws -> [CrashLogInfo]

  func withFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R
}
