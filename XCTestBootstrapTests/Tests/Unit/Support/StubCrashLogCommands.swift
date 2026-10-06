/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Answers with `crash` only if it matches the lookup's predicate, so a predicate that misses
/// the crash of the process being waited on fails the lookup.
struct StubCrashLogCommands: CrashLogCommands {

  private struct CrashDoesNotMatch: Error {}

  let crash: @Sendable () async throws -> CrashLogInfo

  func notifyOfCrash(matching predicate: NSPredicate) async throws -> CrashLogInfo {
    let crash = try await crash()
    guard predicate.evaluate(with: crash) else {
      throw CrashDoesNotMatch()
    }
    return crash
  }

  func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [CrashLogInfo] {
    fatalError("Not used by these tests")
  }

  func prune(matching predicate: NSPredicate) async throws -> [CrashLogInfo] {
    fatalError("Not used by these tests")
  }

  func withFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    fatalError("Not used by these tests")
  }
}
