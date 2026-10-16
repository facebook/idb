/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

extension CrashLogCommands {

  /// Waits for the next crash log matching `predicate`, failing with `timeoutError` if none appears
  /// within `timeout`.
  func notifyOfCrash(matching predicate: CrashLogPredicate, within timeout: TimeInterval, orThrow timeoutError: any Error) async throws -> CrashLogInfo {
    let query = CrashLogQuery(crashLogCommands: self, predicate: predicate)
    return try await withTimeout(timeout, orThrow: { timeoutError }) {
      try await query.next()
    }
  }
}

/// `CrashLogCommands` is not Sendable; the query is only ever used by the one child task that waits
/// on it.
private struct CrashLogQuery: @unchecked Sendable {
  let crashLogCommands: any CrashLogCommands
  let predicate: CrashLogPredicate

  func next() async throws -> CrashLogInfo {
    try await crashLogCommands.notifyOfCrash(matching: predicate)
  }
}
