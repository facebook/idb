/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBControlCore
@testable import FBVideoCore
import Foundation
import Testing

/// `DataConsumer.hasCapacityForFrame`: async consumers report overflow, sync consumers never do.
@Suite
struct ConsumerBackpressureTests {

  @Test
  func hasCapacityWhenNotOverflown() {
    let consumer = AccumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    // AccumulatingBuffer does not queue, so it always has capacity.
    #expect(consumer.hasCapacityForFrame(logger: logger))
  }

  @Test
  func hasNoCapacityWhenOverflown() {
    let consumer = OverflownConsumerDouble()
    let logger = ControlCoreLoggerDouble()

    consumer.setUnprocessedDataCount(0)
    #expect(consumer.hasCapacityForFrame(logger: logger))

    // MaxAllowedUnprocessedDataCounts is 2; > 2 triggers drop
    consumer.setUnprocessedDataCount(3)
    #expect(!consumer.hasCapacityForFrame(logger: logger))
  }
}
