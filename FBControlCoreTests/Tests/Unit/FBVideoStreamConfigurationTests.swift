/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

final class FBVideoStreamConfigurationTests: XCTestCase {
  func testDefaultRateControl() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.H264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    XCTAssertEqual(config.rateControl.mode, .constantQuality)
    XCTAssertEqual(config.rateControl.value, NSNumber(value: 0.75))
  }

  func testDefaultKeyFrameRate() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.H264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    XCTAssertEqual(config.keyFrameRate, NSNumber(value: 1.0))
  }

  func testExplicitQualityPreserved() {
    let rc = FBVideoStreamRateControl.quality(NSNumber(value: 0.7))
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.H264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: rc,
      scaleFactor: nil,
      keyFrameRate: NSNumber(value: 5.0)
    )
    XCTAssertEqual(config.rateControl.mode, .constantQuality)
    XCTAssertEqual(config.rateControl.value, NSNumber(value: 0.7))
    XCTAssertEqual(config.keyFrameRate, NSNumber(value: 5.0))
  }

  func testExplicitBitratePreserved() {
    let rc = FBVideoStreamRateControl.bitrate(NSNumber(value: 500000))
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.H264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: rc,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    XCTAssertEqual(config.rateControl.mode, .averageBitrate)
    XCTAssertEqual(config.rateControl.value, NSNumber(value: 500000))
  }

  func testConfigurationEquality() {
    let rc = FBVideoStreamRateControl.quality(NSNumber(value: 0.5))
    let a = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.H264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: NSNumber(value: 30),
      rateControl: rc,
      scaleFactor: nil,
      keyFrameRate: NSNumber(value: 5.0)
    )
    let b = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.H264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: NSNumber(value: 30),
      rateControl: FBVideoStreamRateControl.quality(NSNumber(value: 0.5)),
      scaleFactor: nil,
      keyFrameRate: NSNumber(value: 5.0)
    )
    XCTAssertEqual(a, b)
  }

  func testConfigurationCopy() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: FBVideoStreamCodec.H264, transport: FBVideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let copy = config.copy() as! FBVideoStreamConfiguration
    XCTAssertEqual(config, copy)
  }

  func testRateControlEquality() {
    let a = FBVideoStreamRateControl.quality(NSNumber(value: 0.5))
    let b = FBVideoStreamRateControl.quality(NSNumber(value: 0.5))
    let c = FBVideoStreamRateControl.bitrate(NSNumber(value: 500000))
    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }
}
