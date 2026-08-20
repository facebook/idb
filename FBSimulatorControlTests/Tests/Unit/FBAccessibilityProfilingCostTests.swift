/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Properties of the profiling collector that the read path depends on.
final class FBAccessibilityProfilingCostTests: XCTestCase {

  // `fetchedKeys` is a set bounded by distinct keys; `attributeFetchCount` is a counter. Pinned
  // separately so a change to either is attributable.
  func testTheFetchedKeySetDoesNotGrowWithCallCount() {
    let collector = FBAccessibilityProfilingCollector()
    for _ in 0..<10000 {
      collector.incrementAttributeFetchCount(forKey: "AXLabel")
    }
    XCTAssertEqual(
      collector.fetchedKeys, ["AXLabel"],
      "the key set is bounded by distinct keys, not by how often they were fetched"
    )
    XCTAssertEqual(collector.attributeFetchCount, 10000)
  }
}
