/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public extension DataConsumer {
  /// Whether the consumer can take another frame. An asynchronous consumer that already holds more
  /// than `maximumQueuedFrames` unprocessed items is behind; the caller should drop the frame rather
  /// than let the queue grow. Synchronous consumers apply their own back-pressure and always accept.
  func hasCapacityForFrame(logger: any ControlCoreLogger) -> Bool {
    guard let asyncConsumer = self as? DataConsumerAsync else {
      return true
    }
    let queued = asyncConsumer.unprocessedDataCount()
    if queued > Self.maximumQueuedFrames {
      logger.log("Consumer is overflown. Number of unsent frames: \(queued)")
      return false
    }
    return true
  }

  private static var maximumQueuedFrames: Int { 2 }
}
