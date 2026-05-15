/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import IDBCompanionUtilities
import XCTest

class AtomicTests: XCTestCase {

  func testAtomicSync() throws {
    @Atomic var counter = 0

    let iterationCount = 1000
    DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
      _counter.sync {
        $0 += 1
      }
    }

    XCTAssertEqual(counter, iterationCount, "Counters don't match. Caution: this may be flaky, because it tests possible race condition.")
  }

  func testConcurrentReadNoCrash() {
    @Atomic var counter = 10

    DispatchQueue.concurrentPerform(iterations: 1000) { _ in
      XCTAssertEqual(counter, 10, "This should never fail, we test for concurrent read crashes")
    }
  }

  func testAtomicSet() {
    @Atomic var counter = 0
    @Atomic var testableCounter = 0

    let iterationCount = 1000
    DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in

      // We assume that "sync" works and use that as a reference to test "set"
      let etalonCounter = _counter.sync { c -> Int in
        c += 1
        return c
      }
      _testableCounter.set(etalonCounter)
    }

    XCTAssertEqual(counter, iterationCount, "Conters not match. Caution: this maby flacky, because tests possible race condition.")
  }
}
