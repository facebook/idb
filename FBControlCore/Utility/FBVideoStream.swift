/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Streams Bitmaps to a File Sink.
@objc public protocol FBVideoStream {
  /// A Future that resolves when the stream has completed.
  @objc var completed: FBFuture<NSNull> { get }

  /// Starts the Streaming, to a Data Consumer.
  func startStreaming(_ consumer: FBDataConsumer) -> FBFuture<NSNull>

  /// Stops the Streaming.
  func stopStreaming() -> FBFuture<NSNull>
}

extension FBVideoStream {
  /// Waits for the stream to complete.
  public func awaitCompletion() async throws {
    try await bridgeFBFutureVoid(self.completed)
  }

  /// Async wrapper for `startStreaming(_:)`.
  public func startStreamingAsync(_ consumer: any FBDataConsumer) async throws {
    try await bridgeFBFutureVoid(startStreaming(consumer))
  }

  /// Async wrapper for `stopStreaming()`.
  public func stopStreamingAsync() async throws {
    try await bridgeFBFutureVoid(stopStreaming())
  }
}
