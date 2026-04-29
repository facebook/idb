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

  /// The teardown extracted from `FBFutureContext.enter:` was not captured.
  /// This indicates the context's `enter:` block was never invoked, even though
  /// the surrounding future resolved successfully.
  case contextTeardownNotCaptured
}

// MARK: - FBFuture → async bridge

/// Wraps a non-`Sendable` `FBFuture` so it can be captured by `@Sendable`
/// closures (the cancellation handler). `FBFuture` is internally serialised by
/// its own dispatch queue, so this is safe in practice.
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
/// Mirrors the `BridgeFuture.value` API in `CompanionLib`, but lives in
/// `FBControlCore` so callers below `CompanionLib` can use it. It will be
/// removed once the underlying `FBFuture` types disappear.
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
/// Mirrors `BridgeFuture.values` but lives in `FBControlCore`. Cancellation of
/// the surrounding `Task` cancels every in-flight future.
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

// MARK: - FBFutureContext → async bridge

/// Wraps a non-`Sendable` `FBFutureContext` so it can survive crossing the
/// `Sendable` boundary of the bridging machinery.
private final class FBFutureContextBox<T: AnyObject>: @unchecked Sendable {
  let context: FBFutureContext<T>
  init(_ context: FBFutureContext<T>) {
    self.context = context
  }
}

/// A box for the context value and its teardown trigger, captured inside the
/// `enter:` block so they survive across the `await` that follows.
private final class ContextEnterCapture<T: AnyObject>: @unchecked Sendable {
  var value: T?
  var teardown: FBMutableFuture<NSNull>?
}

/// Acquires the resource produced by an `FBFutureContext`, runs `body`, then
/// triggers the context's teardown stack.
///
/// This is the async counterpart of the `FBFutureContext` LIFO-teardown API
/// (`pend`/`push`/`pop`/`contextualTeardown`). The resource lifetime is scoped
/// to the duration of `body`. If `body` throws, the teardown still runs and
/// the original error is rethrown.
///
/// Internally uses `FBFutureContext.enter:` to extract the value and the
/// teardown trigger; the teardown trigger is resolved after `body` returns
/// (or throws).
public func withFBFutureContext<T: AnyObject, R>(
  _ context: FBFutureContext<T>,
  body: (T) async throws -> R
) async throws -> R {
  let capture = ContextEnterCapture<T>()
  let contextBox = FBFutureContextBox(context)

  // Use `enter:` to extract both the value and a teardown trigger. We don't
  // care about the value the block returns (it just feeds the surrounding
  // future); we only need the side-effect of capturing.
  let extracted = contextBox.context.onQueue(
    asyncBridgeQueue,
    enter: { value, teardown in
      capture.value = value
      capture.teardown = teardown
      return NSNull()
    })

  // The `enter:`-derived future resolves as soon as the block runs. Awaiting
  // it ensures the capture has been populated and surfaces any failure that
  // occurred while acquiring the underlying resource.
  // swiftlint:disable:next force_cast
  let extractedTyped = extracted as! FBFuture<NSNull>
  _ = try await bridgeFBFuture(extractedTyped)

  guard let value = capture.value, let teardown = capture.teardown else {
    throw AsyncFBFutureBridgeError.contextTeardownNotCaptured
  }

  do {
    let result = try await body(value)
    teardown.resolve(withResult: NSNull())
    return result
  } catch {
    teardown.resolve(withResult: NSNull())
    throw error
  }
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

/// Bridges Swift concurrency back to the `FBFuture` world.
///
/// Used by classes that still need to satisfy a legacy `@objc` protocol
/// returning `FBFuture<T>` while implementing the work natively in
/// `async`/`await`. Cancellation propagates from the returned future to the
/// surrounding task.
///
/// The `job` closure is *not* required to be `@Sendable`: callers frequently
/// capture `self` from non-`Sendable` command classes whose internal
/// serialisation is provided by their work queue. The job runs on exactly one
/// task, so wrapping it via `@unchecked Sendable` is safe in practice.
///
/// `Success` is not constrained to `Sendable` because the existing
/// FBFuture-backed model types (e.g. `NSData`) are not `Sendable`-annotated.
/// The job's result is consumed by the future's resolution exactly once, so
/// unchecked sendability is safe in practice. This is implemented as a free
/// function rather than a `Task` static member so the surrounding `Task<T,
/// Error>` type need not satisfy its own `Success: Sendable` constraint.
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

// MARK: - Internal

let asyncBridgeQueue = DispatchQueue(label: "com.facebook.fbcontrolcore.async_bridge")
