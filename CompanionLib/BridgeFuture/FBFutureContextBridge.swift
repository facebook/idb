/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
@preconcurrency import FBControlCore
import Foundation

/// Awaits the value of an `FBFutureContext` and registers its teardown with the
/// current `FBTeardownContext` so it fires when the surrounding handler scope
/// exits via `FBTeardownContext.withAutocleanup`.
///
/// Use `withFBFutureContext` instead when the resource lifetime should be
/// scoped to a single closure.
func bridgeFBFutureContext<T: AnyObject>(_ futureContext: FBFutureContext<T>) async throws -> T {
  try FBTeardownContext.current.addCleanup {
    let cleanupFuture = futureContext.onQueue(BridgeQueues.futureSerialFullfillmentQueue) { (_: Any, teardown: FBMutableFuture<NSNull>) -> NSNull in
      teardown.resolve(withResult: NSNull())
      return NSNull()
    }
    try await bridgeFBFutureVoid(cleanupFuture)
  }
  return try await bridgeFBFuture(futureContext.future)
}

/// The way the array bridge fails on an unexpected element type, as data rather than an assembled string.
public enum FBFutureBridgeError: Error, LocalizedError {
  case unexpectedArrayElementType(expected: String, array: NSArray)

  public var errorDescription: String? {
    switch self {
    case let .unexpectedArrayElementType(expected, array):
      return "Expected the future to resolve with an array of \(expected), got \(array)"
    }
  }
}

/// `FBFutureContext` array overload that bridges the resolved `NSArray` to `[T]`,
/// throwing when the future resolved with elements of another type.
func bridgeFBFutureContextArray<T>(_ futureContext: FBFutureContext<NSArray>) async throws -> [T] {
  let array = try await bridgeFBFutureContext(futureContext)
  guard let typed = array as? [T] else {
    throw FBFutureBridgeError.unexpectedArrayElementType(expected: String(describing: T.self), array: array)
  }
  return typed
}
