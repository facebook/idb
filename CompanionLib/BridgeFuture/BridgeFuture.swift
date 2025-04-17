/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import IDBCompanionUtilities

enum FBFutureError: Error {

  /// This indicates an error in objc code where result callback was called but no error or result provided. In case of this, debug `FBFuture` implementation.
  case continuationFullfilledWithoutValues

  /// This indicates an error in `BridgeFuture.values` implementation. In case of this, debug `BridgeFuture.values` implementation.
  case taskGroupReceivedNilResultInternalError
}

/// Swift compiler does not allow usage of generic parameters of objc classes in extension
/// so we need to create a bridge for convenience.
public enum BridgeFuture {

  /// Use this to receive results from multiple futures. The results are **ordered in the same order as passed futures**, so you can safely access them from
  /// array by indexes.
  /// - Note: We should *not* use @discardableResult, results should be dropped explicitly by the callee.
  public static func values<T: AnyObject>(_ futures: FBFuture<T>...) async throws -> [T] {
    let futuresArr: [FBFuture<T>] = futures
    return try await values(futuresArr)
  }

  /// Use this to receive results from multiple futures. The results are **ordered in the same order as passed futures**, so you can safely access them from
  /// array by indexes.
  /// - Note: We should *not* use @discardableResult, results should be dropped explicitly by the callee.
  public static func values<T: AnyObject>(_ futures: [FBFuture<T>]) async throws -> [T] {
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
  /// - Note: We should *not* use @discardableResult, results should be dropped explicitly by the callee.
  public static func value<T: AnyObject>(_ future: FBFuture<T>) async throws -> T {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        future.onQueue(
          BridgeQueues.futureSerialFullfillmentQueue,
          notifyOfCompletion: { resultFuture in
            if let error = resultFuture.error {
              continuation.resume(throwing: error)
            } else if let value = resultFuture.result {
              // swiftlint:disable force_cast
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

  /// Awaitable value that waits for publishing from the wrapped future.
  /// This is convenient bridgeable overload for dealing with objc `NSArray`.
  /// - Warning: This operation not safe (as most of objc bridge). That means you should be sure that type bridging will succeed.
  /// Consider this method as
  ///
  /// ```
  /// // ------- command_executor.m
  ///  - (FBFuture<NSArray<NSNumer> *> *)doTheThing;
  ///
  /// // ------- swiftfile.swift
  /// let futureFromObjc: FBFuture<NSArray> = command_executor.doTheThing() // Note: NSNumber is lost
  /// let withoutBridge = BridgeFuture.value(futureFromObjc) // withoutBridge: NSArray
  /// let withBridge: [NSNumer] = BridgeFuture.value(futureFromObjc) // withBridge: [NSNumber]
  ///
  /// // But this starts to shine more when you have to pass results to methods/return results, e.g.
  /// func operation() -> [Int] {
  ///   return BridgeFuture.value(futureFromObjc)
  /// }
  ///
  /// // Or pass value to some oter method
  /// func someMethod(accepts: [NSNumber]) { ... }
  ///
  ///  self.someMethod(accepts: BridgeFuture.value(futureFromObjc)
  /// ```
  public static func value<T>(_ future: FBFuture<NSArray>) async throws -> [T] {
    let objcValue = try await value(future)
    // swiftlint:disable force_cast
    return objcValue as! [T]
  }

  /// Awaitable value that waits for publishing from the wrapped future.
  /// This is convenient bridgeable overload for dealing with objc `NSDictionary`.
  /// - Warning: This operation not safe (as most of objc bridge). That means you should be sure that type bridging will succeed.
  /// Consider this method as
  ///
  /// ```
  /// // ------- command_executor.m
  ///  - (FBFuture<NSDictionary<FBInstalledApplication *, id> *> *)doTheThing;
  ///
  /// // ------- swiftfile.swift
  /// let futureFromObjc: FBFuture<NSDictionary> = command_executor.doTheThing() // Note: types is lost
  /// let withoutBridge = BridgeFuture.value(futureFromObjc) // withoutBridge: NSDictionary
  /// let withBridge: [FBInstalledApplication: Any] = BridgeFuture.value(futureFromObjc) // withBridge: [FBInstalledApplication: Any]
  ///
  /// // But this starts to shine more when you have to pass results to methods/return results, e.g.
  /// func operation() -> [FBInstalledApplication: Any] {
  ///   return BridgeFuture.value(futureFromObjc)
  /// }
  ///
  /// // Or pass value to some oter method
  /// func someMethod(accepts: [FBInstalledApplication: Any]) { ... }
  ///
  ///  self.someMethod(accepts: BridgeFuture.value(futureFromObjc)
  /// ```
  public static func value<T: Hashable, U>(_ future: FBFuture<NSDictionary>) async throws -> [T: U] {
    let objcValue = try await value(future)
    // swiftlint:disable force_cast
    return objcValue as! [T: U]
  }

  /// NSNull is Void equivalent in objc reference world. So is is safe to ignore the result.
  public static func await(_ future: FBFuture<NSNull>) async throws {
    _ = try await Self.value(future)
  }

  /// This overload exists because of `FBMutableFuture` does not convert its exact generic type automatically but it can be automatically converted to `FBFuture<AnyObject>`
  /// without any problems. This decision may be revisited in future.
  public static func await(_ future: FBFuture<AnyObject>) async throws {
    _ = try await Self.value(future)
  }

  /// Interop between swift and objc generics are quite bad, so we have to write wrappers like this.
  /// By default swift bridge compiler could not convert generic type of `FBMutableFuture`. But this force cast is 100% valid and works in runtime
  /// so we just use this little helper.
  public static func convertToFuture<T: AnyObject>(_ mutableFuture: FBMutableFuture<T>) -> FBFuture<T> {
    let future: FBFuture<AnyObject> = mutableFuture
    // swiftlint:disable force_cast
    return future as! FBFuture<T>
  }

  /// Split FBFutureContext to two pieces: result and later cleanup closure
  /// - Parameter futureContext: source future context
  /// - Returns: Tuple of extracted result and cleanup closure that **should** be called later to perform all required cleanups
  public static func value<T: AnyObject>(_ futureContext: FBFutureContext<T>) async throws -> T {
    try FBTeardownContext.current.addCleanup {
      let cleanupFuture = futureContext.onQueue(BridgeQueues.futureSerialFullfillmentQueue) { (result: Any, teardown: FBMutableFuture<NSNull>) -> NSNull in
        teardown.resolve(withResult: NSNull())
        return NSNull()
      }
      try await BridgeFuture.await(cleanupFuture)
    }

    return try await value(futureContext.future)
  }

  /// Awaitable value that waits for publishing from the wrapped futureContext.
  /// This is convenient bridgeable overload for dealing with objc `NSArray`.
  /// - Warning: This operation not safe (as most of objc bridge). That means you should be sure that type bridging will succeed.
  /// Consider this method as
  ///
  /// ```
  /// // ------- command_executor.m
  ///  - (FBFuture<NSArray<NSNumer> *> *)doTheThing;
  ///
  /// // ------- swiftfile.swift
  /// let futureFromObjc: FBFuture<NSArray> = command_executor.doTheThing() // Note: NSNumber is lost
  /// let withoutBridge = BridgeFuture.value(futureFromObjc) // withoutBridge: NSArray
  /// let withBridge: [NSNumer] = BridgeFuture.value(futureFromObjc) // withBridge: [NSNumber]
  ///
  /// // But this starts to shine more when you have to pass results to methods/return results, e.g.
  /// func operation() -> [Int] {
  ///   return BridgeFuture.value(futureFromObjc)
  /// }
  ///
  /// // Or pass value to some oter method
  /// func someMethod(accepts: [NSNumber]) { ... }
  ///
  ///  self.someMethod(accepts: BridgeFuture.value(futureFromObjc)
  /// ```
  public static func values<T: AnyObject, U>(_ futureContext: FBFutureContext<T>) async throws -> [U] {
    let objcValue = try await value(futureContext)
    // swiftlint:disable force_cast
    return objcValue as! [U]
  }
}
