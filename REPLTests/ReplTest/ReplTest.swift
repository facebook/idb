/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import NumberMangler
import XCTest

final class ReplTest: XCTestCase {
  func testMangleZero() {
    XCTAssertEqual(NumberMangler.mangle(0), 42)
  }

  func testMangleNegative() {
    XCTAssertEqual(NumberMangler.mangle(-1), 21)
  }

  func testManglePowerOfTwo() {
    XCTAssertEqual(NumberMangler.mangle(8), 29)
  }
}
