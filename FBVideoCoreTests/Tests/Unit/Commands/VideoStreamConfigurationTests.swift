/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
@testable import FBVideoCore
import Foundation
import Testing

@Suite
struct VideoStreamConfigurationTests {
  @Test
  func unsetFieldsTakeTheirDefaults() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: VideoStreamCodec.h264, transport: VideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    #expect(config.rateControl == .automatic)
    #expect(config.keyFrameRate == 4.0)
    #expect(config.display == .active)
  }

  @Test
  func theDisplayIsKeptAndDescribed() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: VideoStreamCodec.h264, transport: VideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil,
      display: .display(uniqueID: "FA9C9507")
    )
    #expect(config.display == .display(uniqueID: "FA9C9507"))
    #expect(config.description.hasSuffix("| Display FA9C9507"), "\(config.description)")
  }

  /// Only nil takes the default, so a caller mapping an unset wire field has to send nil — zero
  /// survives, and zero is what VideoToolbox reads as an unlimited key frame interval.
  @Test
  func zeroKeyFrameRateIsNotTheDefault() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: VideoStreamCodec.h264, transport: VideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: 0
    )
    #expect(config.keyFrameRate == 0)
  }

  @Test
  func explicitQualityPreserved() {
    let rc = VideoStreamRateControl.quality(0.7)
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: VideoStreamCodec.h264, transport: VideoStreamTransport.annexB),
      framesPerSecond: nil,
      rateControl: rc,
      scaleFactor: nil,
      keyFrameRate: 5.0
    )
    #expect(config.rateControl == .quality(0.7))
    #expect(config.keyFrameRate == 5.0)
  }
}
