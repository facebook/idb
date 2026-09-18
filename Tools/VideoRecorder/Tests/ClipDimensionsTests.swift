/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import SimulatorVideo
import Testing

@Suite struct ClipDimensionsTests {
  @Test func encodesAtTheRecordingsOwnSizeAndRate() {
    let dimensions = ClipDimensions(size: CGSize(width: 590, height: 1278), dataRate: 2_500_000)

    #expect(dimensions.width == 590)
    #expect(dimensions.height == 1278)
    #expect(dimensions.bitRate == 2_500_000)
  }

  @Test func roundsAnOddSizeDownToWhatH264Accepts() {
    let dimensions = ClipDimensions(size: CGSize(width: 589, height: 1277.6), dataRate: 1_000)

    #expect(dimensions.width == 588)
    #expect(dimensions.height == 1276)
  }

  @Test(arguments: [Float(0), .infinity, .nan, -1_000])
  func picksARateForARecordingThatReportsNone(dataRate: Float) {
    let dimensions = ClipDimensions(size: CGSize(width: 100, height: 200), dataRate: dataRate)

    #expect(dimensions.bitRate == 100 * 200 * 4)
  }

  @Test func refusesToEncodeFewerThanTwoPixels() {
    let dimensions = ClipDimensions(
      size: CGSize(width: CGFloat(0), height: CGFloat.nan), dataRate: 1_000)

    #expect(dimensions.width == 2)
    #expect(dimensions.height == 2)
  }
}
