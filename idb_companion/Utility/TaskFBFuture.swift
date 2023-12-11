/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import Foundation

extension Task where Failure == Error, Success: AnyObject & Sendable {

  /// Bridges swift concurrency back to FBFuture world.
  /// - Parameters:
  ///   - job: Asynchronous task
  /// - Returns: Job result
  /// - Note: Job starts its execution instantly and do not wait for FBFuture observation.
  /// - Note: FBFuture cancellation propagates to task.
  static func fbFuture(job: @escaping @Sendable () async throws -> Success) -> FBFuture<Success> {
    let mutableFuture = FBMutableFuture<Success>()

    let task = Task<Void, Error> {
      do {
        let result = try await job()
        mutableFuture.resolve(withResult: result)
      } catch {
        mutableFuture.resolveWithError(error)
      }
    }

    mutableFuture.onQueue(BridgeQueues.miscEventReaderQueue) {
      task.cancel()
      return FBFuture<NSNull>.empty()
    }

    return mutableFuture as! FBFuture<Success>
  }
}
