/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let MaxAllowedUnprocessedDataCounts: Int = 2

/// False when an async consumer has more than `MaxAllowedUnprocessedDataCounts` frames queued, in
/// which case the caller should drop the frame.
public func checkConsumerBufferLimit(_ consumer: any DataConsumer, _ logger: any ControlCoreLogger) -> Bool {
  if let asyncConsumer = consumer as? DataConsumerAsync {
    let framesInProcess = asyncConsumer.unprocessedDataCount()
    if framesInProcess > MaxAllowedUnprocessedDataCounts {
      logger.log("Consumer is overflown. Number of unsent frames: \(framesInProcess)")
      return false
    }
  }
  return true
}
