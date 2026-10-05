/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A profiler that has started.
public struct ProfileOperation: Sendable {
  /// Every sample a `resources` profiler takes; finishes immediately for every other profiler.
  public let samples: AsyncStream<ResourceSample>
  private let task: Task<ProfileResult, Error>

  public init(samples: AsyncStream<ResourceSample> = AsyncStream { $0.finish() }, task: Task<ProfileResult, Error>) {
    self.samples = samples
    self.task = task
  }

  /// Returns once the profiler finishes, throwing if its tool failed.
  public var result: ProfileResult {
    get async throws { try await task.value }
  }

  /// Ends a `resources` profiler. Any other profiler is cancelled, so `result` throws `CancellationError`.
  public func stop() {
    task.cancel()
  }
}
