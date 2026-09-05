/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBVideoStreamConfigurationTests: XCTestCase {
  func testDefaultRateControl() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.h264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    XCTAssertEqual(config.rateControl, .automatic)
  }

  func testDefaultKeyFrameRate() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.h264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    XCTAssertEqual(config.keyFrameRate, 4.0)
  }

  /// Only nil takes the default, so a caller mapping an unset wire field has to send nil — zero
  /// survives, and zero is what VideoToolbox reads as an unlimited key frame interval.
  func testZeroKeyFrameRateIsNotTheDefault() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.h264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: 0
    )
    XCTAssertEqual(config.keyFrameRate, 0)
  }

  func testExplicitQualityPreserved() {
    let rc = FBVideoStreamRateControl.quality(0.7)
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.h264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: rc,
      scaleFactor: nil,
      keyFrameRate: 5.0
    )
    XCTAssertEqual(config.rateControl, .quality(0.7))
    XCTAssertEqual(config.keyFrameRate, 5.0)
  }

  func testConfigurationEquality() {
    let rc = FBVideoStreamRateControl.quality(0.5)
    let a = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.h264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: 30,
      rateControl: rc,
      scaleFactor: nil,
      keyFrameRate: 5.0
    )
    let b = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.h264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: 30,
      rateControl: FBVideoStreamRateControl.quality(0.5),
      scaleFactor: nil,
      keyFrameRate: 5.0
    )
    XCTAssertEqual(a, b)
  }

  func testRateControlEquality() {
    let a = FBVideoStreamRateControl.quality(0.5)
    let b = FBVideoStreamRateControl.quality(0.5)
    let c = FBVideoStreamRateControl.bitrate(500000)
    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }
}
