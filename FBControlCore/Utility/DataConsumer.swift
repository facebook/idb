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
public protocol DataConsumer: Sendable {
  /// Consumes the provided binary data.
  func consumeData(_ data: Data)

  /// Consumes an end-of-file.
  func consumeEndOfFile()

  /// When this consumer is done with the data it is handed.
  var consumption: DataConsumption { get }
}

public extension DataConsumer {
  var consumption: DataConsumption { .unspecified }
}

/// When a consumer is done with the data it is handed.
public enum DataConsumption: Equatable, Sendable {
  /// Each chunk is consumed before `consumeData` returns, so the caller may hand over bytes it does not own.
  case synchronous
  /// Chunks are consumed later, and `unprocessed` are still waiting.
  case queued(unprocessed: Int)
  /// No promise either way, so the caller must hand over bytes it owns.
  case unspecified
}

/// Observation of a Data Consumer's lifecycle.
public protocol DataConsumerLifecycle: Sendable {
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
public final class FBLoggingDataConsumer: DataConsumer {
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
public final class FBCompositeDataConsumer: DataConsumer, DataConsumerLifecycle, CustomStringConvertible, @unchecked Sendable {
  private let consumers: [DataConsumer]
  private let finishedConsumingFuture = FBMutableFuture<NSNull>()

  public init(consumers: [DataConsumer]) {
    self.consumers = consumers
  }

  public var description: String {
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
public final class FBNullDataConsumer: DataConsumer {
  public init() {}

  public func consumeData(_ data: Data) {}

  public func consumeEndOfFile() {}
}
