/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import VideoToolbox
import XCTest

final class FBSimulatorVideoStreamCompressionPropertiesTests: XCTestCase {

  func testMJPEGEncoderRequiresHardwareAccelerationByDefault() throws {
    guard #available(macOS 12.1, *) else {
      throw XCTSkip("Required hardware acceleration starts on macOS 12.1")
    }
    let specification =
      FBSimulatorVideoStreamFramePusher_VideoToolbox.encoderSpecification(
        for: .mjpeg(encoder: .requireHardware)
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

  func testMJPEGEncoderAllowsSoftwareEncodingWhenOptedIn() {
    let specification =
      FBSimulatorVideoStreamFramePusher_VideoToolbox.encoderSpecification(
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
      FBSimulatorVideoStreamFramePusher_VideoToolbox.encoderSpecification(
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
      FBSimulatorVideoStreamFramePusher_VideoToolbox.encoderSpecification(
        for: .minicap
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

  func testMJPEGEncoderSelectionAffectsConfigurationIdentity() {
    let hardwareConfiguration = FBVideoStreamConfiguration(
      format: .mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let softwareConfiguration = FBVideoStreamConfiguration(
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
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_RealTime as String] as? NSNumber, true)
    XCTAssertEqual(props[kVTCompressionPropertyKey_AllowFrameReordering as String] as? NSNumber, false)
    // No rateControl set: `.automatic` — the pusher derives an AverageBitRate at session setup, so
    // the properties dictionary carries no rate key for compressed video.
    XCTAssertNil(props[kVTCompressionPropertyKey_Quality as String])
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
    XCTAssertEqual(props[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String] as? NSNumber, 1.0)
  }

  func testCallerPropertiesMerged() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let callerProps: [String: Any] = ["CustomKey": 42]
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: callerProps)
    XCTAssertEqual(props["CustomKey"] as? NSNumber, 42)
  }

  // MARK: - Compression Quality

  func testMJPEGCompressionPropertiesContainQuality() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: FBVideoStreamRateControl.quality(0.5),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.5)
  }

  func testMinicapCompressionPropertiesContainQuality() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.minicap,
      framesPerSecond: nil,
      rateControl: FBVideoStreamRateControl.quality(0.5),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.5)
  }

  func testH264CompressionPropertiesContainQuality() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: FBVideoStreamRateControl.quality(0.5),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.5)
  }

  func testAutomaticRateControlAddsNoRateKeyForH264() {
    // `.automatic` defers to session setup, where the output dimensions derive an AverageBitRate;
    // the properties dictionary itself must carry neither a bitrate nor the (encoder-ignored)
    // Quality key.
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
    XCTAssertNil(props[kVTCompressionPropertyKey_Quality as String])
  }

  func testAutomaticRateControlUsesQualityForMJPEG() {
    // JPEG encoders honor the quality knob, so `.automatic` keeps the pre-automatic default there.
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.75)
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
  }

  func testAutomaticAverageBitRateScalesWithOutputPixels() {
    // 4 bits per output pixel per second: native 3x retina, half scale, and a small stream.
    XCTAssertEqual(FBSimulatorVideoStreamFramePusher_VideoToolbox.automaticAverageBitRate(width: 1206, height: 2622), 12_648_528)
    XCTAssertEqual(FBSimulatorVideoStreamFramePusher_VideoToolbox.automaticAverageBitRate(width: 604, height: 1312), 3_169_792)
    XCTAssertEqual(FBSimulatorVideoStreamFramePusher_VideoToolbox.automaticAverageBitRate(width: 640, height: 480), 1_228_800)
  }

  // MARK: - H264 Encoding-Specific Properties

  func testH264ProfileAndEntropyMode() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertNotNil(props[kVTCompressionPropertyKey_ProfileLevel as String])
    XCTAssertNotNil(props[kVTCompressionPropertyKey_H264EntropyMode as String])
  }

  // MARK: - Bitrate Configuration

  func testExplicitBitrate() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.mjpeg(encoder: .requireHardware),
      framesPerSecond: nil,
      rateControl: FBVideoStreamRateControl.bitrate(500000),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_AverageBitRate as String] as? NSNumber, 500000)
  }

  // MARK: - HEVC Encoding-Specific Properties

  func testHEVCProfileAndClosedGOP() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: .hevc, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    // HEVC uses a closed GOP and an HEVC Main/Main10 profile.
    XCTAssertEqual(props[kVTCompressionPropertyKey_AllowOpenGOP as String] as? NSNumber, false)
    let profile = props[kVTCompressionPropertyKey_ProfileLevel as String] as? String
    XCTAssertNotNil(profile)
    XCTAssertTrue(
      profile == (kVTProfileLevel_HEVC_Main_AutoLevel as String) || profile == (kVTProfileLevel_HEVC_Main10_AutoLevel as String),
      "HEVC profile should be Main or Main10, got \(String(describing: profile))"
    )
    // HEVC must not set the H264-specific entropy mode.
    XCTAssertNil(props[kVTCompressionPropertyKey_H264EntropyMode as String])
  }

  // MARK: - Low-Latency Base Properties

  func testBasePropertiesUseZeroMaxFrameDelay() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    // Zero frame delay keeps the live stream low-latency.
    XCTAssertEqual(props[kVTCompressionPropertyKey_MaxFrameDelayCount as String] as? NSNumber, 0)
  }
}

/// Tests for the single output-dimension computation shared by the VideoToolbox session setup and
/// the composited-frame pool — the two sites that must agree exactly.
final class FBVideoOutputDimensionsTests: XCTestCase {

  private let zeroInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0)

  func testEvenSourcePassesThroughUnchanged() {
    let dims = FBVideoOutputDimensions.calculate(sourceWidth: 1206, sourceHeight: 2622, scaleFactor: nil, edgeInsets: zeroInsets)
    XCTAssertEqual(dims, FBVideoOutputDimensions(width: 1206, height: 2622))
  }

  func testOddDimensionsRoundUpToEven() {
    let dims = FBVideoOutputDimensions.calculate(sourceWidth: 101, sourceHeight: 55, scaleFactor: nil, edgeInsets: zeroInsets)
    XCTAssertEqual(dims, FBVideoOutputDimensions(width: 102, height: 56))
  }

  func testFractionalScaleFloorsThenRoundsToEven() {
    // 1206 * 0.5 = 603 (odd) → 604; 2622 * 0.5 = 1311 (odd) → 1312.
    let dims = FBVideoOutputDimensions.calculate(sourceWidth: 1206, sourceHeight: 2622, scaleFactor: 0.5, edgeInsets: zeroInsets)
    XCTAssertEqual(dims, FBVideoOutputDimensions(width: 604, height: 1312))
  }

  func testInsetsExpandBeforeEvenRounding() {
    // 100 + (3 + 4) = 107 → 108; 200 + (5 + 0) = 205 → 206.
    let insets = FBVideoStreamEdgeInsets(top: 5, bottom: 0, left: 3, right: 4)
    let dims = FBVideoOutputDimensions.calculate(sourceWidth: 100, sourceHeight: 200, scaleFactor: nil, edgeInsets: insets)
    XCTAssertEqual(dims, FBVideoOutputDimensions(width: 108, height: 206))
  }

  func testScaleAppliesBeforeInsets() {
    // floor(1000 * 0.25) = 250, + (10 + 10) = 270; floor(500 * 0.25) = 125, + (20 + 25) = 170.
    let insets = FBVideoStreamEdgeInsets(top: 20, bottom: 25, left: 10, right: 10)
    let dims = FBVideoOutputDimensions.calculate(sourceWidth: 1000, sourceHeight: 500, scaleFactor: 0.25, edgeInsets: insets)
    XCTAssertEqual(dims, FBVideoOutputDimensions(width: 270, height: 170))
  }

  func testOutOfRangeScaleFactorsAreIgnored() {
    // Only factors strictly between 0 and 1 apply — 1.0, >1, 0, and negative are all pass-through.
    for factor in [1.0, 2.0, 0.0, -0.5] {
      let dims = FBVideoOutputDimensions.calculate(sourceWidth: 640, sourceHeight: 480, scaleFactor: factor, edgeInsets: zeroInsets)
      XCTAssertEqual(dims, FBVideoOutputDimensions(width: 640, height: 480), "factor \(factor) must not scale")
    }
  }
}
