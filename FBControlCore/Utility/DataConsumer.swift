/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A consumer of NSData.
///
/// Every consumer is handed bytes from one thread and read or finished from another — that is what a
/// consumer is for — so the protocols are `Sendable`: a conformer is either confined to one queue,
/// immutable, or locked, and says which.
@objc public protocol DataConsumer: NSObjectProtocol, Sendable {
  /// Consumes the provided binary data.
  func consumeData(_ data: Data)

  /// Consumes an end-of-file.
  func consumeEndOfFile()
}

/// A consumer of dispatch_data.
@objc public protocol DispatchDataConsumer: NSObjectProtocol, Sendable {
  /// Consumes the provided binary data.
  func consumeData(_ data: __DispatchData)

  /// Consumes an end-of-file.
  func consumeEndOfFile()
}

/// Consumer which consumes the data synchronously in the same context as the caller invoking consumeData.
@objc public protocol DataConsumerSync: NSObjectProtocol, Sendable {
}

/// Consumer which consumes the data asynchronously.
@objc public protocol DataConsumerAsync: NSObjectProtocol, Sendable {
  /// Number of submitted data that has not been consumed yet.
  func unprocessedDataCount() -> Int
}

/// Observation of a Data Consumer's lifecycle.
@objc public protocol DataConsumerLifecycle: NSObjectProtocol, Sendable {
  /// A Future that resolves when there is no more data to write and any underlying resource managed by the consumer is released.
  var finishedConsuming: FBFuture<NSNull> { get }
}

public extension DataConsumerLifecycle {
  /// Awaits completion of `finishedConsuming`.
  func awaitFinishedConsuming() async throws {
    try await bridgeFBFutureVoid(self.finishedConsuming)
  }
}

// MARK: - Conformance extensions for ObjC classes

extension FBLoggingDataConsumer: DataConsumer {}
extension FBCompositeDataConsumer: DataConsumer, DataConsumerLifecycle {}
extension FBNullDataConsumer: DataConsumer {}
