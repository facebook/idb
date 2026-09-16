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

final class SimulatorVideoStreamCompressionPropertiesTests: XCTestCase {

  func testMJPEGEncoderRequiresHardwareAccelerationByDefault() throws {
    guard #available(macOS 12.1, *) else {
      throw XCTSkip("Required hardware acceleration starts on macOS 12.1")
    }
    let specification =
      SimulatorVideoStreamFramePusher_VideoToolbox.encoderSpecification(
        for: .mjpeg(encoder: .requireHardware)
      )

    XCTAssertEqual(
      specification[
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder
          as String
      ] as? Bool,
      true
    )
    XCTAssertNil(
      specification[
        kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String
      ]
    )
    XCTAssertNil(
      specification[
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
          as String
      ]
    )
  }

  func testMJPEGEncoderAllowsSoftwareEncodingWhenOptedIn() {
    let specification =
      SimulatorVideoStreamFramePusher_VideoToolbox.encoderSpecification(
        for: .mjpeg(encoder: .allowSoftware)
      )

    XCTAssertEqual(
      specification[
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
          as String
      ] as? Bool,
      true
    )
    XCTAssertNil(
      specification[
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder
          as String
      ]
    )
    XCTAssertNil(
      specification[
        kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String
      ]
    )
  }

  func testCompressedVideoRequiresHardwareAcceleration() throws {
    guard #available(macOS 12.1, *) else {
      throw XCTSkip("Required hardware acceleration starts on macOS 12.1")
    }
    let specification =
      SimulatorVideoStreamFramePusher_VideoToolbox.encoderSpecification(
        for: .compressedVideo(withCodec: .h264, transport: .annexB)
      )

    XCTAssertEqual(
      specification[
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder
          as String
      ] as? Bool,
      true
    )
    XCTAssertEqual(
      specification[
        kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String
      ] as? Bool,
      true
    )
    XCTAssertNil(
      specification[
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
          as String
      ]
    )
  }

  func testMinicapRequiresHardwareAcceleration() throws {
    guard #available(macOS 12.1, *) else {
      throw XCTSkip("Required hardware acceleration starts on macOS 12.1")
    }
    let specification =
      SimulatorVideoStreamFramePusher_VideoToolbox.encoderSpecification(
        for: .minicap
      )

    XCTAssertEqual(
      specification[
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder
          as String
      ] as? Bool,
      true
    )
    XCTAssertNil(
      specification[
        kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String
      ]
    )
    XCTAssertNil(
      specification[
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
          as String
      ]
    )
  }

  func testMJPEGEncoderSelectionAffectsConfigurationIdentity() {
    let hardwareConfiguration = VideoStreamConfiguration(
      format: .mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let softwareConfiguration = VideoStreamConfiguration(
      format: .mjpeg(encoder: .allowSoftware),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )

    XCTAssertNotEqual(hardwareConfiguration, softwareConfiguration)
  }

  // MARK: - Shared Properties

  func testBasePropertiesAlwaysPresent() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_RealTime as String] as? NSNumber, true)
    XCTAssertEqual(props[kVTCompressionPropertyKey_AllowFrameReordering as String] as? NSNumber, false)
    // No rateControl set: `.automatic` — the pusher derives an AverageBitRate at session setup, so
    // the properties dictionary carries no rate key for compressed video.
    XCTAssertNil(props[kVTCompressionPropertyKey_Quality as String])
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
    XCTAssertEqual(props[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String] as? NSNumber, 4.0)
  }

  func testCallerPropertiesMerged() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let callerProps: [String: Any] = ["CustomKey": 42]
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: callerProps)
    XCTAssertEqual(props["CustomKey"] as? NSNumber, 42)
  }

  // MARK: - Compression Quality

  func testMJPEGCompressionPropertiesContainQuality() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: VideoStreamRateControl.quality(0.5),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.5)
  }

  func testH264CompressionPropertiesContainQuality() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: VideoStreamRateControl.quality(0.5),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    // Compressed video carries no rate key here; the pusher resolves quality to a bitrate at setup.
    XCTAssertNil(props[kVTCompressionPropertyKey_Quality as String])
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
  }

  func testH264ExplicitBitrateIsResolvedAtSetupNotInSharedProperties() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: VideoStreamRateControl.bitrate(500000),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
  }

  // MARK: - Compressed Video Rate Control

  private func rateControlProperties(_ rateControl: VideoStreamRateControl) -> [String: Any] {
    SimulatorVideoStreamFramePusher_VideoToolbox.compressedVideoRateControlProperties(rateControl: rateControl, width: 1206, height: 2622)
  }

  func testAutomaticRateControlResolvesToTheAutomaticBudget() {
    let props = rateControlProperties(.automatic)
    XCTAssertEqual(props[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 12_648_528)
    XCTAssertNil(props[kVTCompressionPropertyKey_Quality as String])
  }

  func testQualityRateControlScalesTheAutomaticBudget() {
    XCTAssertEqual(rateControlProperties(.quality(0.75))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 12_648_528)
    XCTAssertEqual(rateControlProperties(.quality(0.375))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 6_324_264)
    XCTAssertEqual(rateControlProperties(.quality(1.0))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 16_864_704)
    XCTAssertNil(rateControlProperties(.quality(0.5))[kVTCompressionPropertyKey_Quality as String])
  }

  func testQualityRateControlClampsOutOfRangeValues() {
    XCTAssertEqual(
      rateControlProperties(.quality(7))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int,
      rateControlProperties(.quality(1))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int)
    XCTAssertGreaterThan(rateControlProperties(.quality(0))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int ?? 0, 0)
  }

  func testExplicitBitrateRateControlPassesThrough() {
    XCTAssertEqual(rateControlProperties(.bitrate(4_000_000))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 4_000_000)
  }

  func testRateControlBoundsBurstsToOneAndAHalfTimesTheAverageOverOneSecond() {
    let limits = rateControlProperties(.bitrate(8_000_000))[kVTCompressionPropertyKey_DataRateLimits as String] as? [NSNumber]
    // 8 Mbps × 1.5 = 12 Mbit = 1.5 MB per one-second window.
    XCTAssertEqual(limits, [1_500_000, 1])
  }

  func testAutomaticRateControlUsesQualityForMJPEG() {
    // JPEG encoders honor the quality knob, so `.automatic` uses it for MJPEG.
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.75)
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
  }

  func testAutomaticAverageBitRateScalesWithOutputPixels() {
    // 4 bits per output pixel per second: native 3x retina, half scale, and a small stream.
    XCTAssertEqual(SimulatorVideoStreamFramePusher_VideoToolbox.automaticAverageBitRate(width: 1206, height: 2622), 12_648_528)
    XCTAssertEqual(SimulatorVideoStreamFramePusher_VideoToolbox.automaticAverageBitRate(width: 604, height: 1312), 3_169_792)
    XCTAssertEqual(SimulatorVideoStreamFramePusher_VideoToolbox.automaticAverageBitRate(width: 640, height: 480), 1_228_800)
  }

  // MARK: - H264 Encoding-Specific Properties

  func testH264ProfileAndEntropyMode() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertNotNil(props[kVTCompressionPropertyKey_ProfileLevel as String])
    XCTAssertNotNil(props[kVTCompressionPropertyKey_H264EntropyMode as String])
  }

  // MARK: - Bitrate Configuration

  func testExplicitBitrate() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: VideoStreamRateControl.bitrate(500000),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_AverageBitRate as String] as? NSNumber, 500000)
  }

  // MARK: - HEVC Encoding-Specific Properties

  func testHEVCProfileAndClosedGOP() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: .hevc, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_AllowOpenGOP as String] as? NSNumber, false)
    XCTAssertEqual(props[kVTCompressionPropertyKey_ProfileLevel as String] as? String, kVTProfileLevel_HEVC_Main_AutoLevel as String)
    XCTAssertNil(props[kVTCompressionPropertyKey_H264EntropyMode as String])
  }

  // MARK: - Cadence Properties

  private func makeStream(framesPerSecond: Int?) -> SimulatorVideoStream {
    let configuration = VideoStreamConfiguration(
      format: .compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: framesPerSecond,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let framebuffer = Framebuffer(surface: FakeFramebufferSurface(), logger: CapturingLogger())
    return SimulatorVideoStream.make(framebuffer: framebuffer, configuration: configuration, logger: CapturingLogger())
  }

  func testLazyCadenceAddsNoProperties() async {
    let props = await makeStream(framesPerSecond: nil).compressionSessionProperties
    XCTAssertTrue(props.isEmpty)
  }

  func testEagerCadenceSetsExpectedFrameRateOnly() async {
    let props = await makeStream(framesPerSecond: 60).compressionSessionProperties
    XCTAssertEqual(props[kVTCompressionPropertyKey_ExpectedFrameRate as String] as? NSNumber, 60)
    XCTAssertNil(props[kVTCompressionPropertyKey_MaxKeyFrameInterval as String])
  }

  // MARK: - Low-Latency Base Properties

  func testBasePropertiesUseZeroMaxFrameDelay() {
    let config = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = SimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    // Zero frame delay keeps the live stream low-latency.
    XCTAssertEqual(props[kVTCompressionPropertyKey_MaxFrameDelayCount as String] as? NSNumber, 0)
  }
}

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
