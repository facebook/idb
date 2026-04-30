/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBLogOperation`.
/// Returns a long-lived operation that can be awaited for completion or cancelled.
public protocol AsyncLogOperation: AnyObject {

  /// The data consumer attached to the underlying log stream.
  var consumer: any FBDataConsumer { get }

  /// Awaits completion of the log operation. Cancelling the calling task signals
  /// the operation to terminate.
  func waitUntilCompleted() async throws
}

/// Swift-native async/await counterpart of `FBLogCommands`.
public protocol AsyncLogCommands: AnyObject {

  func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any AsyncLogOperation
}

/// Adapter wrapping a legacy `FBLogOperation` in `AsyncLogOperation` shape so
/// the default bridge can return a Swift-native handle. Cancellation of the
/// awaiting task signals the underlying operation through `FBFuture.cancel()`.
public final class AsyncLogOperationBridge: AsyncLogOperation {

  public let consumer: any FBDataConsumer
  private let underlying: any FBLogOperation

  public init(_ underlying: any FBLogOperation) {
    self.underlying = underlying
    self.consumer = underlying.consumer
  }

  public func waitUntilCompleted() async throws {
    try await bridgeFBFutureVoid(underlying.completed)
  }
}

/// Default bridge implementation against the legacy `FBLogCommands` protocol.
extension AsyncLogCommands where Self: FBLogCommands {

  public func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any AsyncLogOperation {
    let operation = try await bridgeFBFuture(self.tailLog(arguments, consumer: consumer))
    return AsyncLogOperationBridge(operation)
  }
}
