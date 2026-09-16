/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import VideoToolbox
import XCTest

/// Tests for the single output-dimension computation shared by the VideoToolbox session setup and
/// the composited-frame pool — the two sites that must agree exactly.
final class VideoOutputDimensionsTests: XCTestCase {

  private let zeroInsets = VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0)

  func testEvenSourcePassesThroughUnchanged() {
    let dims = VideoOutputDimensions.calculate(sourceWidth: 1206, sourceHeight: 2622, scaleFactor: nil, edgeInsets: zeroInsets)
    XCTAssertEqual(dims, VideoOutputDimensions(width: 1206, height: 2622))
  }

  func testOddDimensionsRoundUpToEven() {
    let dims = VideoOutputDimensions.calculate(sourceWidth: 101, sourceHeight: 55, scaleFactor: nil, edgeInsets: zeroInsets)
    XCTAssertEqual(dims, VideoOutputDimensions(width: 102, height: 56))
  }

  func testFractionalScaleFloorsThenRoundsToEven() {
    // 1206 * 0.5 = 603 (odd) → 604; 2622 * 0.5 = 1311 (odd) → 1312.
    let dims = VideoOutputDimensions.calculate(sourceWidth: 1206, sourceHeight: 2622, scaleFactor: 0.5, edgeInsets: zeroInsets)
    XCTAssertEqual(dims, VideoOutputDimensions(width: 604, height: 1312))
  }

  func testInsetsExpandBeforeEvenRounding() {
    // 100 + (3 + 4) = 107 → 108; 200 + (5 + 0) = 205 → 206.
    let insets = VideoStreamEdgeInsets(top: 5, bottom: 0, left: 3, right: 4)
    let dims = VideoOutputDimensions.calculate(sourceWidth: 100, sourceHeight: 200, scaleFactor: nil, edgeInsets: insets)
    XCTAssertEqual(dims, VideoOutputDimensions(width: 108, height: 206))
  }

  func testScaleAppliesBeforeInsets() {
    // floor(1000 * 0.25) = 250, + (10 + 10) = 270; floor(500 * 0.25) = 125, + (20 + 25) = 170.
    let insets = VideoStreamEdgeInsets(top: 20, bottom: 25, left: 10, right: 10)
    let dims = VideoOutputDimensions.calculate(sourceWidth: 1000, sourceHeight: 500, scaleFactor: 0.25, edgeInsets: insets)
    XCTAssertEqual(dims, VideoOutputDimensions(width: 270, height: 170))
  }

  func testOutOfRangeScaleFactorsAreIgnored() {
    // Only factors strictly between 0 and 1 apply — 1.0, >1, 0, and negative are all pass-through.
    for factor in [1.0, 2.0, 0.0, -0.5] {
      let dims = VideoOutputDimensions.calculate(sourceWidth: 640, sourceHeight: 480, scaleFactor: factor, edgeInsets: zeroInsets)
      XCTAssertEqual(dims, VideoOutputDimensions(width: 640, height: 480), "factor \(factor) must not scale")
    }
  }
}
