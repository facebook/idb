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
    // No rateControl set: quality mode with default 0.75
    XCTAssertEqual(props[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.75)
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
    XCTAssertEqual(props[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String] as? NSNumber, 1.0)
  }

  func testCallerPropertiesMerged() {
    let config = FBVideoStreamConfiguration(
      format: FBVideoStreamFormat.mjpeg(),
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
      format: FBVideoStreamFormat.mjpeg(),
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
      format: FBVideoStreamFormat.minicap(),
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
      format: FBVideoStreamFormat.mjpeg(),
      framesPerSecond: nil,
      rateControl: FBVideoStreamRateControl.bitrate(500000),
      scaleFactor: nil,
      keyFrameRate: nil
    )
    let props = FBSimulatorVideoStream.compressionSessionProperties(for: config, callerProperties: [:])
    XCTAssertEqual(props[kVTCompressionPropertyKey_AverageBitRate as String] as? NSNumber, 500000)
  }
}
