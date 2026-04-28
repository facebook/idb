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

// MARK: - Internal

let asyncBridgeQueue = DispatchQueue(label: "com.facebook.fbcontrolcore.async_bridge")
