/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import SimulatorIPC
import XCTest

final class IPCFrameTests: XCTestCase {
  func testFrameBoundsAreIdenticalInBothDirections() throws {
    XCTAssertEqual(try IPCFrame.header(forSize: 258), Data([0, 0, 1, 2]))
    for size in [1, IPCFrame.maximumSize] {
      XCTAssertEqual(try IPCFrame.size(fromHeader: IPCFrame.header(forSize: size)), size)
    }
    for size in [0, -1, IPCFrame.maximumSize + 1] {
      XCTAssertThrowsError(try IPCFrame.header(forSize: size)) {
        XCTAssertEqual($0 as? IPCError, .invalidFrameSize(size))
      }
    }
    for header in [Data(), Data([0, 0, 0]), Data([0, 0, 0, 0]), Data([1, 0, 0, 1]), Data([255, 255, 255, 255])] {
      XCTAssertThrowsError(try IPCFrame.size(fromHeader: header))
    }
  }
}
