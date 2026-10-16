/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension DispatchQueue {

  /// Runs `work` on this queue and returns its result, or throws its error. For blocking calls that
  /// must stay off Swift concurrency's threads, and for state only this queue touches.
  ///
  /// `work` need not be `Sendable`: it runs exactly once, on this queue, and nothing else holds it.
  public func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
    let job = QueueJob(work)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
      self.async {
        continuation.resume(with: Result { try job.work() })
      }
    }
  }

  /// As `perform(_:)`, for work that cannot fail.
  public func perform<T>(_ work: @escaping () -> T) async -> T {
    let job = QueueJob(work)
    return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
      self.async {
        continuation.resume(returning: job.work())
      }
    }
  }
}

/// `@unchecked Sendable`: the job is handed to exactly one queue block and only ever run there.
private final class QueueJob<Work>: @unchecked Sendable {
  let work: Work

  init(_ work: Work) {
    self.work = work
  }
}
