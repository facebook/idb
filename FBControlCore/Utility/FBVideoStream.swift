/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A handle to a running video stream. It is returned already streaming; call `stop()` to end it.
public protocol FBVideoStream: AnyObject {
  /// A Future that resolves when the stream has completed.
  var completed: FBFuture<NSNull> { get }

  /// Stops the stream and waits for it to finish.
  func stop() async throws
}

extension FBVideoStream {
  /// Waits for the stream to complete.
  public func awaitCompletion() async throws {
    try await bridgeFBFutureVoid(self.completed)
  }
}
