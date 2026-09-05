/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Streams encoded video frames to a data consumer. `Sendable` because the async lifecycle methods
/// are awaited across concurrency domains.
public protocol FBVideoStream: AnyObject, Sendable {
  /// Starts the Streaming, to a Data Consumer.
  func startStreaming(_ consumer: FBDataConsumer) async throws

  /// Stops the Streaming.
  func stopStreaming() async throws

  /// Waits for the stream to complete (returns once it has stopped).
  func awaitCompletion() async throws
}
