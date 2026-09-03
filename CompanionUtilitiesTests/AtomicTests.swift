/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionUtilities
import Foundation
import Testing

@Suite
struct AtomicTests {

  @Test
  func atomicSync() throws {
    @Atomic var counter = 0

    let iterationCount = 1000
    DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
      _counter.sync {
        $0 += 1
      }
    }

    #expect(counter == iterationCount, "Counters don't match. Caution: this may be flaky, because it tests possible race condition.")
  }

  @Test
  func concurrentReadNoCrash() {
    @Atomic var counter = 10

    DispatchQueue.concurrentPerform(iterations: 1000) { _ in
      #expect(counter == 10, "This should never fail, we test for concurrent read crashes")
    }
  }

  @Test
  func atomicSet() {
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

    #expect(counter == iterationCount, "Conters not match. Caution: this maby flacky, because tests possible race condition.")
  }
}
