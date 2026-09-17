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

/// What a `VTCompressionSession` is told for each format, rate control, cadence and sink.
final class VideoToolboxEncoderSettingsTests: XCTestCase {

  private static let retinaWidth = 1206
  private static let retinaHeight = 2622

  private func settings(
    _ format: VideoStreamFormat,
    rateControl: VideoStreamRateControl? = nil,
    framesPerSecond: Int? = nil,
    keyFrameRate: Double? = nil,
    sink: VideoEncodeSink = .live
  ) -> VideoToolboxEncoderSettings {
    let configuration = VideoStreamConfiguration(
      format: format, framesPerSecond: framesPerSecond, rateControl: rateControl, scaleFactor: nil, keyFrameRate: keyFrameRate)
    let cadence: VideoStreamCadence = framesPerSecond.map { .eager(framesPerSecond: UInt($0)) } ?? .lazy
    return VideoToolboxEncoderSettings(configuration: configuration, cadence: cadence, sink: sink)
  }

  private func retinaProperties(_ settings: VideoToolboxEncoderSettings) -> [String: Any] {
    settings.sessionProperties(outputWidth: Self.retinaWidth, outputHeight: Self.retinaHeight)
  }

  private let h264 = VideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB)
  private let hevc = VideoStreamFormat.compressedVideo(withCodec: .hevc, transport: .annexB)
  private let mjpeg = VideoStreamFormat.mjpeg(encoder: .requireHardware)

  // MARK: - Encoder specification

  func testMJPEGEncoderRequiresHardwareAccelerationByDefault() throws {
    guard #available(macOS 12.1, *) else {
      throw XCTSkip("Required hardware acceleration starts on macOS 12.1")
    }
    let specification = settings(mjpeg).encoderSpecification
    XCTAssertEqual(specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String] as? Bool, true)
    XCTAssertNil(specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String])
    XCTAssertNil(specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String])
  }

  func testMJPEGEncoderAllowsSoftwareEncodingWhenOptedIn() {
    let specification = settings(.mjpeg(encoder: .allowSoftware)).encoderSpecification
    XCTAssertEqual(specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String] as? Bool, true)
    XCTAssertNil(specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String])
    XCTAssertNil(specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String])
  }

  func testCompressedVideoRequiresHardwareAccelerationWithLowLatencyRateControl() throws {
    guard #available(macOS 12.1, *) else {
      throw XCTSkip("Required hardware acceleration starts on macOS 12.1")
    }
    let specification = settings(h264).encoderSpecification
    XCTAssertEqual(specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String] as? Bool, true)
    XCTAssertEqual(specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String] as? Bool, true)
    XCTAssertNil(specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String])
  }

  func testMinicapRequiresHardwareAcceleration() throws {
    guard #available(macOS 12.1, *) else {
      throw XCTSkip("Required hardware acceleration starts on macOS 12.1")
    }
    let specification = settings(.minicap).encoderSpecification
    XCTAssertEqual(specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String] as? Bool, true)
    XCTAssertNil(specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String])
    XCTAssertNil(specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String])
  }

  func testMJPEGEncoderSelectionAffectsConfigurationIdentity() {
    let hardware = VideoStreamConfiguration(format: .mjpeg(encoder: .requireHardware), framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)
    let software = VideoStreamConfiguration(format: .mjpeg(encoder: .allowSoftware), framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)
    XCTAssertNotEqual(hardware, software)
  }

  // MARK: - Shared session properties

  func testLiveSinkIsRealTimeWithNoReorderingOrDelay() {
    let props = retinaProperties(settings(h264))
    XCTAssertEqual(props[kVTCompressionPropertyKey_RealTime as String] as? NSNumber, true)
    XCTAssertEqual(props[kVTCompressionPropertyKey_AllowFrameReordering as String] as? NSNumber, false)
    XCTAssertEqual(props[kVTCompressionPropertyKey_MaxFrameDelayCount as String] as? NSNumber, 0)
    XCTAssertEqual(props[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String] as? NSNumber, 4.0)
  }

  func testKeyFrameRateIsTheOnlyKeyFrameControl() {
    let props = retinaProperties(settings(h264, framesPerSecond: 60, keyFrameRate: 2.5))
    XCTAssertEqual(props[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String] as? NSNumber, 2.5)
    XCTAssertNil(props[kVTCompressionPropertyKey_MaxKeyFrameInterval as String])
  }

  func testFileSinkUsesTheStandardEncoderWithReordering() {
    let fileSettings = settings(h264, framesPerSecond: 30, sink: .file)
    let props = retinaProperties(fileSettings)
    XCTAssertEqual(props[kVTCompressionPropertyKey_RealTime as String] as? NSNumber, true)
    XCTAssertEqual(props[kVTCompressionPropertyKey_AllowFrameReordering as String] as? NSNumber, true)
    XCTAssertNil(props[kVTCompressionPropertyKey_MaxFrameDelayCount as String])

    let specification = fileSettings.encoderSpecification
    XCTAssertEqual(specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String] as? Bool, true)
    XCTAssertNil(specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String])
  }

  // MARK: - Cadence

  func testLazyCadenceSetsNoExpectedFrameRate() {
    XCTAssertNil(retinaProperties(settings(h264))[kVTCompressionPropertyKey_ExpectedFrameRate as String])
  }

  func testEagerCadenceSetsExpectedFrameRate() {
    XCTAssertEqual(retinaProperties(settings(h264, framesPerSecond: 60))[kVTCompressionPropertyKey_ExpectedFrameRate as String] as? NSNumber, 60)
  }

  // MARK: - Codec properties

  func testH264ProfileAndEntropyMode() {
    let props = retinaProperties(settings(h264))
    XCTAssertEqual(props[kVTCompressionPropertyKey_ProfileLevel as String] as? String, kVTProfileLevel_H264_High_AutoLevel as String)
    XCTAssertEqual(props[kVTCompressionPropertyKey_H264EntropyMode as String] as? String, kVTH264EntropyMode_CABAC as String)
  }

  func testHEVCProfileAndClosedGOP() {
    let props = retinaProperties(settings(hevc))
    XCTAssertEqual(props[kVTCompressionPropertyKey_AllowOpenGOP as String] as? NSNumber, false)
    XCTAssertEqual(props[kVTCompressionPropertyKey_ProfileLevel as String] as? String, kVTProfileLevel_HEVC_Main_AutoLevel as String)
    XCTAssertNil(props[kVTCompressionPropertyKey_H264EntropyMode as String])
  }

  // MARK: - JPEG rate control

  func testJPEGSessionsGetNoReorderingOrDelayKeys() {
    for sink in [VideoEncodeSink.live, .file] {
      let props = retinaProperties(settings(mjpeg, sink: sink))
      XCTAssertNil(props[kVTCompressionPropertyKey_AllowFrameReordering as String], "\(sink)")
      XCTAssertNil(props[kVTCompressionPropertyKey_MaxFrameDelayCount as String], "\(sink)")
    }
  }

  func testAutomaticRateControlUsesQualityForMJPEG() {
    let props = retinaProperties(settings(mjpeg))
    XCTAssertEqual(props[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.75)
    XCTAssertNil(props[kVTCompressionPropertyKey_AverageBitRate as String])
  }

  func testMJPEGQualityPassesThrough() {
    XCTAssertEqual(retinaProperties(settings(mjpeg, rateControl: .quality(0.5)))[kVTCompressionPropertyKey_Quality as String] as? NSNumber, 0.5)
  }

  func testMJPEGBitratePassesThrough() {
    XCTAssertEqual(retinaProperties(settings(mjpeg, rateControl: .bitrate(500000)))[kVTCompressionPropertyKey_AverageBitRate as String] as? NSNumber, 500000)
  }

  // MARK: - Compressed video rate control

  func testCompressedVideoNeverSetsTheQualityProperty() {
    for rateControl: VideoStreamRateControl in [.automatic, .quality(0.5), .bitrate(500000)] {
      XCTAssertNil(retinaProperties(settings(h264, rateControl: rateControl))[kVTCompressionPropertyKey_Quality as String], "\(rateControl)")
    }
  }

  func testAutomaticRateControlResolvesToTheAutomaticBudget() {
    XCTAssertEqual(retinaProperties(settings(h264))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 12_648_528)
  }

  func testQualityRateControlScalesTheAutomaticBudget() {
    XCTAssertEqual(retinaProperties(settings(h264, rateControl: .quality(0.75)))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 12_648_528)
    XCTAssertEqual(retinaProperties(settings(h264, rateControl: .quality(0.375)))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 6_324_264)
    XCTAssertEqual(retinaProperties(settings(h264, rateControl: .quality(1.0)))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 16_864_704)
  }

  func testQualityRateControlClampsOutOfRangeValues() {
    XCTAssertEqual(
      retinaProperties(settings(h264, rateControl: .quality(7)))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int,
      retinaProperties(settings(h264, rateControl: .quality(1)))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int)
    XCTAssertGreaterThan(retinaProperties(settings(h264, rateControl: .quality(0)))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int ?? 0, 0)
  }

  func testExplicitBitrateRateControlPassesThrough() {
    XCTAssertEqual(retinaProperties(settings(h264, rateControl: .bitrate(4_000_000)))[kVTCompressionPropertyKey_AverageBitRate as String] as? Int, 4_000_000)
  }

  func testRateControlBoundsBurstsToOneAndAHalfTimesTheAverageOverOneSecond() {
    let limits = retinaProperties(settings(h264, rateControl: .bitrate(8_000_000)))[kVTCompressionPropertyKey_DataRateLimits as String] as? [Int]
    // 8 Mbps × 1.5 = 12 Mbit = 1.5 MB per one-second window.
    XCTAssertEqual(limits, [1_500_000, 1])
  }

  func testAutomaticAverageBitRateScalesWithOutputPixels() {
    // 4 bits per output pixel per second: native 3x retina, half scale, and a small stream.
    XCTAssertEqual(VideoToolboxEncoderSettings.automaticAverageBitRate(width: 1206, height: 2622), 12_648_528)
    XCTAssertEqual(VideoToolboxEncoderSettings.automaticAverageBitRate(width: 604, height: 1312), 3_169_792)
    XCTAssertEqual(VideoToolboxEncoderSettings.automaticAverageBitRate(width: 640, height: 480), 1_228_800)
  }

  // MARK: - Pusher construction

  func testRecordingPusherEncodesForAFileSink() throws {
    let config = VideoStreamConfiguration(format: h264, framesPerSecond: 30, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)
    let fileWriter = SimulatorVideoFileWriter(filePath: NSTemporaryDirectory() + "/\(UUID().uuidString).mp4", logger: CapturingLogger())
    let recording = try SimulatorVideoStream.framePusher(
      configuration: config, cadence: .eager(framesPerSecond: 30), consumer: FBNullDataConsumer(),
      encodedSampleConsumerOverride: fileWriter, frameWriters: nil, logger: CapturingLogger())
    XCTAssertEqual((recording as? VideoToolboxFramePusher)?.settings.sink, .file)

    let live = try SimulatorVideoStream.framePusher(
      configuration: config, cadence: .eager(framesPerSecond: 30), consumer: FBNullDataConsumer(),
      encodedSampleConsumerOverride: nil, frameWriters: nil, logger: CapturingLogger())
    XCTAssertEqual((live as? VideoToolboxFramePusher)?.settings.sink, .live)
  }
}
