/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBControlCore
import XCTest

/// `DataConsumer.hasCapacityForFrame`: async consumers report overflow, sync consumers never do.
final class ConsumerBackpressureTests: XCTestCase {

  func testHasCapacityWhenNotOverflown() {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    // AccumulatingBuffer does not conform to DataConsumerAsync,
    // so it always has capacity.
    XCTAssertTrue(consumer.hasCapacityForFrame(logger: logger))
  }

  func testHasNoCapacityWhenOverflown() {
    let consumer = OverflownConsumerDouble()
    let logger = ControlCoreLoggerDouble()

    consumer.setUnprocessedDataCount(0)
    XCTAssertTrue(consumer.hasCapacityForFrame(logger: logger))

    // MaxAllowedUnprocessedDataCounts is 2; > 2 triggers drop
    consumer.setUnprocessedDataCount(3)
    XCTAssertFalse(consumer.hasCapacityForFrame(logger: logger))
  }
}
