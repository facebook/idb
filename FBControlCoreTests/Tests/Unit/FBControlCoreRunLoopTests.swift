/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBControlCoreRunLoopTests: XCTestCase {
  func testNestedAwaiting() throws {
    let future = FBFuture<NSNumber>(
      delay: 0.1,
      future: FBFuture(result: NSNumber(value: true))
    )
    .onQueue(
      DispatchQueue.main,
      map: { _ -> NSNumber? in
        return try? FBFuture<NSNumber>(
          delay: 0.1,
          future: FBFuture(result: NSNumber(value: true))
        )
        .await()
      })

    let result = try future.await()
    XCTAssertNotNil(result)
  }
}
