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
private final class FBFutureBox<T: AnyObject>: @unchecked Sendable {
  let future: FBFuture<T>
  init(_ future: FBFuture<T>) {
    self.future = future
  }
}

/// Carries the resolved value across the continuation boundary without
/// requiring `T` to conform to `Sendable`. The value originates from a single
/// dispatch queue and is consumed by exactly one `await`, so unchecked
/// `Sendable` conformance is safe.
private final class FBFutureResultBox<T>: @unchecked Sendable {
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
  let box = FBFutureBox(future)
  let wrapped = try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FBFutureResultBox<T>, Error>) in
      box.future.onQueue(
        asyncBridgeQueue,
        notifyOfCompletion: { resolved in
          if let error = resolved.error {
            continuation.resume(throwing: error)
          } else if let value = resolved.result {
            // swiftlint:disable:next force_cast
            continuation.resume(returning: FBFutureResultBox(value as! T))
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

/// Awaits an `FBFuture<NSArray>` and force-casts the elements to `[T]`.
///
/// Force-cast is unavoidable because Objective-C generics are erased at the
/// Swift boundary; callers must guarantee the element type matches.
public func bridgeFBFutureArray<T>(_ future: FBFuture<NSArray>) async throws -> [T] {
  let array = try await bridgeFBFuture(future)
  // swiftlint:disable:next force_cast
  return array as! [T]
}

/// Awaits an `FBFuture<NSDictionary>` and force-casts to `[K: V]`.
public func bridgeFBFutureDictionary<K: Hashable, V>(_ future: FBFuture<NSDictionary>) async throws -> [K: V] {
  let dict = try await bridgeFBFuture(future)
  // swiftlint:disable:next force_cast
  return dict as! [K: V]
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

/// Awaits an array of `FBFuture`s in parallel and returns the resolved values
/// in the same order as the inputs.
///
/// Cancellation of the surrounding `Task` cancels every in-flight future.
public func bridgeFBFutures<T: AnyObject>(_ futures: [FBFuture<T>]) async throws -> [T] {
  return try await withThrowingTaskGroup(of: (Int, FBFutureResultBox<T>).self, returning: [T].self) { group in
    var results: [T?] = .init(repeating: nil, count: futures.count)
    for (index, future) in futures.enumerated() {
      let box = FBFutureBox(future)
      group.addTask {
        let value = try await bridgeFBFuture(box.future)
        return (index, FBFutureResultBox(value))
      }
    }
    for try await (index, valueBox) in group {
      results[index] = valueBox.value
    }
    return results.map { value -> T in
      guard let value else {
        preconditionFailure("bridgeFBFutures task group produced nil; unreachable")
      }
      return value
    }
  }
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

/// Awaits an `FBMutableFuture<T>` and returns its resolved value.
func awaitMutableFuture<T: AnyObject>(_ mutableFuture: FBMutableFuture<T>) async throws -> T {
  try await bridgeFBFuture(convertFBMutableFuture(mutableFuture))
}

/// Awaits an `FBMutableFuture<NSNull>`, discarding the resolved `NSNull`.
func awaitMutableFutureVoid(_ mutableFuture: FBMutableFuture<NSNull>) async throws {
  try await bridgeFBFutureVoid(convertFBMutableFuture(mutableFuture))
}

// MARK: - async → FBFuture bridge

/// Wraps a non-`Sendable` async closure so it can be captured by the
/// `@Sendable` operation closure required by `Task.init`. The job runs exactly
/// once on the spawned task, so unchecked sendability is safe in practice.
private final class FBFutureJobBox<Success>: @unchecked Sendable {
  let job: () async throws -> Success
  init(_ job: @escaping () async throws -> Success) {
    self.job = job
  }
}

/// Bridges an async job back to an `FBFuture`, for callers that must satisfy an `FBFuture`-returning
/// protocol. Cancelling the returned future cancels the task. Neither `job` nor `Success` is required to
/// be `Sendable`: the job runs on exactly one task and the result is consumed once by the resolution.
public func fbFutureFromAsync<Success: AnyObject>(
  job: @escaping () async throws -> Success
) -> FBFuture<Success> {
  let mutableFuture = FBMutableFuture<Success>()
  let resultBox = FBFutureResultBox<FBMutableFuture<Success>>(mutableFuture)
  let jobBox = FBFutureJobBox(job)
  let resolverBox = FBFutureResolverBox<Success> { value in
    resultBox.value.resolve(withResult: value)
  } resolveError: { error in
    resultBox.value.resolveWithError(error)
  }

  let task = Task<Void, Error> {
    do {
      let result = try await jobBox.job()
      resolverBox.resolve(result)
    } catch {
      resolverBox.resolveError(error)
    }
  }

  mutableFuture.onQueue(asyncBridgeQueue) {
    task.cancel()
    return FBFuture<NSNull>.empty()
  }

  // swiftlint:disable:next force_cast
  return mutableFuture as! FBFuture<Success>
}

/// Captures the resolution callbacks so the spawned `Task` body never needs
/// to reference the non-`Sendable` `FBMutableFuture` directly.
private final class FBFutureResolverBox<Success>: @unchecked Sendable {
  let resolve: (Success) -> Void
  let resolveError: (Error) -> Void
  init(resolve: @escaping (Success) -> Void, resolveError: @escaping (Error) -> Void) {
    self.resolve = resolve
    self.resolveError = resolveError
  }
}

let asyncBridgeQueue = DispatchQueue(label: "com.facebook.fbcontrolcore.async_bridge")
