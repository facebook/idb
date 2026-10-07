/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors emitted while bridging an `FBFuture` to Swift `async`/`await`.
public enum AsyncFBFutureBridgeError: Error {
  /// The underlying future signalled completion without yielding a value or an
  /// error. This indicates a bug in the producing FBFuture implementation.
  case continuationFulfilledWithoutValues
}

// MARK: - FBFuture → async bridge

/// Wraps a non-`Sendable` `FBFuture` for capture by `@Sendable` closures; `FBFuture` guards its state
/// with `@synchronized`, so sharing it is safe.
private final class FutureBox<T: AnyObject>: @unchecked Sendable {
  let future: FBFuture<T>
  init(_ future: FBFuture<T>) {
    self.future = future
  }
}

/// Carries the resolved value across the continuation boundary without
/// requiring `T` to conform to `Sendable`. The value originates from a single
/// dispatch queue and is consumed by exactly one `await`, so unchecked
/// `Sendable` conformance is safe.
private final class FutureResultBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) {
    self.value = value
  }
}

/// Awaits an `FBFuture` and returns its resolved value.
///
/// Cooperative cancellation is honoured: cancelling the surrounding `Task`
/// also cancels the underlying future via `FBFuture.cancel()`.
///
/// `T` is not constrained to `Sendable` because the existing FBFuture-backed
/// model types are not `Sendable`-annotated; the bridge ferries the value
/// across the continuation through an internal `@unchecked Sendable` wrapper.
public func bridgeFBFuture<T: AnyObject>(_ future: FBFuture<T>) async throws -> T {
  let box = FutureBox(future)
  let wrapped = try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FutureResultBox<T>, Error>) in
      box.future.onQueue(
        asyncBridgeQueue,
        notifyOfCompletion: { resolved in
          if let error = resolved.error {
            continuation.resume(throwing: error)
          } else if let value = resolved.result {
            // swiftlint:disable:next force_cast
            continuation.resume(returning: FutureResultBox(value as! T))
          } else if resolved.state == .cancelled {
            // A cancelled FBFuture has neither `result` nor `error`; surface it as `CancellationError`.
            continuation.resume(throwing: CancellationError())
          } else {
            continuation.resume(throwing: AsyncFBFutureBridgeError.continuationFulfilledWithoutValues)
          }
        })
    }
  } onCancel: {
    box.future.cancel()
  }
  return wrapped.value
}

/// Awaits an `FBFuture<NSNull>`, discarding the resolved `NSNull`.
public func bridgeFBFutureVoid(_ future: FBFuture<NSNull>) async throws {
  _ = try await bridgeFBFuture(future)
}

/// Awaits an `FBFuture<AnyObject>`, discarding the resolved value.
///
/// `FBMutableFuture<T>` does not bridge its exact generic type to Swift, but it
/// is freely convertible to `FBFuture<AnyObject>`. This overload lets such
/// futures be awaited when only completion (not the value) matters.
public func bridgeFBFutureVoid(_ future: FBFuture<AnyObject>) async throws {
  _ = try await bridgeFBFuture(future)
}

/// Force-casts an `FBMutableFuture<T>` to its `FBFuture<T>` parent type.
///
/// Swift's bridge does not preserve the Objective-C generic argument when
/// passing `FBMutableFuture<T>` where `FBFuture<T>` is expected. Using
/// `as! FBFuture<T>` is correct at runtime because the underlying class
/// hierarchy holds the same type parameter.
public func convertFBMutableFuture<T: AnyObject>(_ mutableFuture: FBMutableFuture<T>) -> FBFuture<T> {
  let future: FBFuture<AnyObject> = mutableFuture
  // swiftlint:disable:next force_cast
  return future as! FBFuture<T>
}

let asyncBridgeQueue = DispatchQueue(label: "com.facebook.fbcontrolcore.async_bridge")
