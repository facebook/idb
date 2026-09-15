/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest

final class AccessibilityRuntimeQueueTests: XCTestCase {
  func testWorkerExceptionsReturnToTheMainCallerAndDoNotBlockLaterWork() {
    XCTAssertTrue(Thread.isMainThread)
    for raise in [false, true, false] {
      XCTAssertEqual(
        FBAXRuntimeQueueProbe(raise) as NSDictionary,
        ["offMain": true, "calls": 1, "sameException": raise, "caught": raise] as NSDictionary)
    }
  }

  func testWorkerCallerRunsSynchronouslyAndReceivesTheSameException() {
    let finished = expectation(description: "worker completes")
    DispatchQueue.global().async {
      XCTAssertFalse(Thread.isMainThread)
      for raise in [false, true, false] {
        XCTAssertEqual(
          FBAXRuntimeQueueProbe(raise) as NSDictionary,
          ["offMain": true, "calls": 1, "sameException": raise, "caught": raise] as NSDictionary)
      }
      finished.fulfill()
    }
    wait(for: [finished], timeout: 5)
  }
}
