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
    return try await withThrowingTaskGroup(of: CrashLogBox.self) { group in
      group.addTask {
        try await query.next()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw timeoutError
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else {
        preconditionFailure("The task group has two children; next() cannot be empty")
      }
      return first.value
    }
  }
}

/// `CrashLogCommands` is not Sendable; the query is only ever used by the one child task that waits
/// on it.
private struct CrashLogQuery: @unchecked Sendable {
  let crashLogCommands: any CrashLogCommands
  let predicate: CrashLogPredicate

  func next() async throws -> CrashLogBox {
    CrashLogBox(try await crashLogCommands.notifyOfCrash(matching: predicate))
  }
}

private final class CrashLogBox: @unchecked Sendable {
  let value: CrashLogInfo
  init(_ value: CrashLogInfo) { self.value = value }
}
