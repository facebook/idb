/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import IDBCompanionUtilities

class AtomicTestsTests: XCTestCase {

  func testAtomic() throws {
    @Atomic var counter = 0

    let iterationCount = 1000
    DispatchQueue.concurrentPerform(iterations: iterationCount) { i in
      _counter.sync {
        $0 += 1
      }
    }

    XCTAssertEqual(counter, iterationCount, "Counters don't match. Caution: this may be flaky, because it tests possible race condition.")
  }

}
