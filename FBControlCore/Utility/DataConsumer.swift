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

/// A consumer that logs each received chunk, trimmed of newlines, to `logger`.
public final class FBLoggingDataConsumer: NSObject, DataConsumer {
  public let logger: ControlCoreLogger

  public init(logger: ControlCoreLogger) {
    self.logger = logger
  }

  public func consumeData(_ data: Data) {
    guard let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines), !string.isEmpty else {
      return
    }
    logger.log(string)
  }

  public func consumeEndOfFile() {}
}

/// A consumer that forwards everything it receives to each of `consumers`, in order.
// SAFETY: all state is immutable; `FBMutableFuture` is internally synchronized.
public final class FBCompositeDataConsumer: NSObject, DataConsumer, DataConsumerLifecycle, @unchecked Sendable {
  private let consumers: [DataConsumer]
  private let finishedConsumingFuture = FBMutableFuture<NSNull>()

  public init(consumers: [DataConsumer]) {
    self.consumers = consumers
  }

  override public var description: String {
    "Composite Consumer \(CollectionInformation.oneLineDescription(from: consumers))"
  }

  public func consumeData(_ data: Data) {
    for consumer in consumers {
      consumer.consumeData(data)
    }
  }

  public func consumeEndOfFile() {
    for consumer in consumers {
      consumer.consumeEndOfFile()
    }
    finishedConsumingFuture.resolve(withResult: NSNull())
  }

  public var finishedConsuming: FBFuture<NSNull> {
    finishedConsumingFuture.retyped(FBFuture<NSNull>.self)
  }
}

/// A consumer that discards everything it receives.
public final class FBNullDataConsumer: NSObject, DataConsumer {
  public func consumeData(_ data: Data) {}

  public func consumeEndOfFile() {}
}
