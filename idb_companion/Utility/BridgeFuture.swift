/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import FBControlCore

enum FBFutureError: Error {
  case continuationFullfilledWithoutValues
  case taskGroupReceivedNilResultInternalError
}

/// Swift compiler does not allow usage of generic parameters of objc classes in extension
/// so we need to create a bridge class
enum BridgeFuture {

  static func values<T: AnyObject>(_ futures: FBFuture<T>...) async throws -> [T] {
    let futuresArr: [FBFuture<T>] = futures
    return try await values(futuresArr)
  }

  static func values<T: AnyObject>(_ futures: [FBFuture<T>]) async throws -> [T] {
    return try await withThrowingTaskGroup(of: (Int, T).self, returning: [T].self) { group in
      var results = [T?].init(repeating: nil, count: futures.count)

      for (index, future) in futures.enumerated() {
        group.addTask {
          return try await (index, BridgeFuture.value(future))
        }
      }

      for try await (index, value) in group {
        results[index] = value
      }

      return try results.map { value -> T in
        guard let shouldDefinitelyExist = value else {
          assertionFailure("This should never happen. We should fullfill all values at that moment")
          throw FBFutureError.taskGroupReceivedNilResultInternalError
        }
        return shouldDefinitelyExist
      }
    }
  }

  /// Awaitable value that waits for publishing from the wrapped future
  static func value<T: AnyObject>(_ future: FBFuture<T>) async throws -> T {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        future.onQueue(BridgeQueues.futureSerialFullfillmentQueue, notifyOfCompletion: { resultFuture in
          if let error = resultFuture.error {
            continuation.resume(throwing: error)
          } else if let value = resultFuture.result {
            continuation.resume(returning: value as! T)
          } else {
            continuation.resume(throwing: FBFutureError.continuationFullfilledWithoutValues)
          }
        })
      }
    } onCancel: {
      future.cancel()
    }
  }

  static func await(_ future: FBFuture<NSNull>) async throws {
    _ = try await Self.value(future)
  }

  static func await(_ future: FBFuture<AnyObject>) async throws {
    _ = try await Self.value(future)
  }

  /// Interop between swift and objc generics are quite bad, so we have to write wrappers like this
  static func convertToFuture<T: AnyObject>(_ mutableFuture: FBMutableFuture<T>) -> FBFuture<T> {
    let future: FBFuture<AnyObject> = mutableFuture
    return future as! FBFuture<T>
  }
}
