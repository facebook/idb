/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A consumer of NSData.
@objc public protocol FBDataConsumer: NSObjectProtocol {
  /// Consumes the provided binary data.
  func consumeData(_ data: Data)

  /// Consumes an end-of-file.
  func consumeEndOfFile()
}

/// A consumer of dispatch_data.
@objc public protocol FBDispatchDataConsumer: NSObjectProtocol {
  /// Consumes the provided binary data.
  func consumeData(_ data: __DispatchData)

  /// Consumes an end-of-file.
  func consumeEndOfFile()
}

/// Consumer which consumes the data synchronously in the same context as the caller invoking consumeData.
@objc public protocol FBDataConsumerSync: NSObjectProtocol {
}

/// Consumer which consumes the data asynchronously.
@objc public protocol FBDataConsumerAsync: NSObjectProtocol {
  /// Number of submitted data that has not been consumed yet.
  func unprocessedDataCount() -> Int
}

/// Observation of a Data Consumer's lifecycle.
@objc public protocol FBDataConsumerLifecycle: NSObjectProtocol {
  /// A Future that resolves when there is no more data to write and any underlying resource managed by the consumer is released.
  var finishedConsuming: FBFuture<NSNull> { get }
}

public extension FBDataConsumerLifecycle {
  /// Awaits completion of `finishedConsuming`.
  func awaitFinishedConsumingAsync() async throws {
    try await bridgeFBFutureVoid(self.finishedConsuming)
  }
}

// MARK: - Conformance extensions for ObjC classes

extension FBLoggingDataConsumer: FBDataConsumer {}
extension FBCompositeDataConsumer: FBDataConsumer, FBDataConsumerLifecycle {}
extension FBNullDataConsumer: FBDataConsumer {}
