/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import SimulatorIPC
import Testing

@Suite
struct IPCFrameTests {
  @Test
  func frameBoundsAreIdenticalInBothDirections() throws {
    #expect(try IPCFrame.header(forSize: 258) == Data([0, 0, 1, 2]))
    for size in [1, IPCFrame.maximumSize] {
      #expect(try IPCFrame.size(fromHeader: IPCFrame.header(forSize: size)) == size)
    }
    for size in [0, -1, IPCFrame.maximumSize + 1] {
      #expect(throws: IPCError.invalidFrameSize(size)) { try IPCFrame.header(forSize: size) }
    }
    for header in [Data(), Data([0, 0, 0]), Data([0, 0, 0, 0]), Data([1, 0, 0, 1]), Data([255, 255, 255, 255])] {
      #expect(throws: (any Error).self) { try IPCFrame.size(fromHeader: header) }
    }
  }
}
