/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import FBControlCore

private let futureSerialFullfillmentQueue = DispatchQueue(label: "com.facebook.fbfuture.fullfilment")

enum FBFutureError: Error {
  case continuationFullfilledWithoutValues
}

/// Swift compiler does not allow usage of generic parameters of objc classes in extension
/// so we need to create a bridge class
final class FutureBox<T: AnyObject> {

  let future: FBFuture<T>

  init(_ future: FBFuture<T>) {
    self.future = future
  }

  /// Interop between swift and objc generics are quite bad, so we have to write wrappers like this
  init(_ mutableFuture: FBMutableFuture<T>) {
    let future: FBFuture<AnyObject> = mutableFuture
    self.future = future as! FBFuture<T>
  }

  /// Awaitable value that waits for publishing from the wrapped future
  var value: T {
    get async throws {
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          future.onQueue(futureSerialFullfillmentQueue, notifyOfCompletion: { resultFuture in
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
  }
}

extension FutureBox where T == NSNull {

  /// Created to explicitly indicate that result type is Void and nothing should be returned.
  /// And also to make a difference between omitting from call site
  func await() async throws {
    _ = try await value
  }
}
