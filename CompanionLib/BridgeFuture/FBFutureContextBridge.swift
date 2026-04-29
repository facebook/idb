/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import IDBCompanionUtilities

/// Awaits the value of an `FBFutureContext` and registers its teardown with the
/// current `FBTeardownContext` so it fires when the surrounding handler scope
/// exits via `FBTeardownContext.withAutocleanup`.
///
/// This is the async counterpart to the legacy `BridgeFuture.value(_:)`
/// `FBFutureContext` overload. Use `withFBFutureContext` instead when the
/// resource lifetime should be scoped to a single closure.
public func bridgeFBFutureContext<T: AnyObject>(_ futureContext: FBFutureContext<T>) async throws -> T {
  try FBTeardownContext.current.addCleanup {
    let cleanupFuture = futureContext.onQueue(BridgeQueues.futureSerialFullfillmentQueue) { (_: Any, teardown: FBMutableFuture<NSNull>) -> NSNull in
      teardown.resolve(withResult: NSNull())
      return NSNull()
    }
    try await bridgeFBFutureVoid(cleanupFuture)
  }
  return try await bridgeFBFuture(futureContext.future)
}

/// `FBFutureContext` array overload that force-casts the resolved `NSArray` to
/// `[T]`. Mirrors the `[T]`-returning `BridgeFuture.values(_:)` context overload.
public func bridgeFBFutureContextArray<T>(_ futureContext: FBFutureContext<NSArray>) async throws -> [T] {
  let array = try await bridgeFBFutureContext(futureContext)
  // swiftlint:disable:next force_cast
  return array as! [T]
}
