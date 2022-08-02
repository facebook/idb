/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

struct TaskTimeoutError: Error, LocalizedError {
  let location: CodeLocation

  var errorDescription: String? {
    "Received timeout for task. \(location)"
  }
}

extension Task where Failure == Error {

  /// Awaits certain amount of time for a job throwing an error on timeouts
  /// - Parameters:
  ///   - nanoseconds: Amount of time to wait
  /// - Returns: Job result
  public static func timeout(nanoseconds: UInt64, function: String = #function, file: String = #file, line: Int = #line, column: Int = #column, job: @escaping @Sendable () async throws -> Success) async throws -> Success {
    let jobTask = Task<Success, Error> { try await job() }
    let result = await Task<Success, Error>.select(
      jobTask,
      Task<Success, Error> {
        try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
        throw TaskTimeoutError(location: .init(function: function, file: file, line: line, column: column))
      }
    )
    return try await result.value
  }

}
