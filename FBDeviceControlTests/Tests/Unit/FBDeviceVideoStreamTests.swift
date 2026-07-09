/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import CoreVideo
import FBControlCore
@testable import FBDeviceControl
import XCTest

/// Behavior-lock coverage for the device video stream's format dispatch and per-format frame writing.
/// The capture-session/AVFoundation plumbing (`stream(withSession:...)`, `configureVideoOutput`) is
/// exercised by hardware-gated integration paths; these unit tests cover the format → subclass
/// mapping and each subclass's `consumeSampleBuffer` byte contract by feeding synthesized buffers.
final class FBDeviceVideoStreamTests: XCTestCase {

  // MARK: - Helpers

  private func configuration(_ format: FBVideoStreamFormat) -> FBVideoStreamConfiguration {
    FBVideoStreamConfiguration(format: format, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)
  }

  private func makeStream(for format: FBVideoStreamFormat, consumer: (any FBDataConsumer)?) throws -> FBDeviceVideoStream {
    let streamType = try XCTUnwrap(FBDeviceVideoStream.classForConfiguration(configuration(format)), "Expected a stream type for \(format)")
    let stream = streamType.init(
      session: AVCaptureSession(),
      output: AVCaptureVideoDataOutput(),
      writeQueue: DispatchQueue(label: "test.device.video"),
      logger: CapturingLogger()
    )
    stream.consumer = consumer
    return stream
  }

  // MARK: - Format → subclass dispatch

  func testClassForConfigurationResolvesSupportedFormats() {
    XCTAssertNotNil(FBDeviceVideoStream.classForConfiguration(configuration(.bgra)))
    XCTAssertNotNil(FBDeviceVideoStream.classForConfiguration(configuration(.mjpeg)))
    XCTAssertNotNil(FBDeviceVideoStream.classForConfiguration(configuration(.minicap)))
    XCTAssertNotNil(FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .h264, transport: .annexB))))
    XCTAssertNotNil(FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .h264, transport: .mpegts))))
  }

  func testClassForConfigurationDistinguishesH264Transports() throws {
    let annexB = try XCTUnwrap(FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .h264, transport: .annexB))))
    let mpegts = try XCTUnwrap(FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .h264, transport: .mpegts))))
    XCTAssertTrue(String(describing: annexB).contains("H264"))
    XCTAssertTrue(String(describing: mpegts).contains("MPEGTS"))
    XCTAssertFalse(annexB == mpegts)
  }

  func testClassForConfigurationRejectsHEVC() {
    // HEVC is not yet supported on the device path (added later in the overhaul).
    XCTAssertNil(FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .hevc, transport: .annexB))))
    XCTAssertNil(FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .hevc, transport: .mpegts))))
  }

  // MARK: - consumeSampleBuffer byte contracts

  func testBGRAWritesRawPixelBytes() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .bgra, consumer: consumer)
    let sampleBuffer = makeBGRASampleBuffer(width: 16, height: 8, fill: 0xAB)
    let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!

    stream.consumeSampleBuffer(sampleBuffer)

    let output = consumer.data()
    XCTAssertFalse(output.isEmpty)
    XCTAssertEqual(output.count, CVPixelBufferGetDataSize(pixelBuffer))
    XCTAssertTrue(output.allSatisfy { $0 == 0xAB }, "BGRA bytes should pass through unchanged")
  }

  func testH264ProducesAnnexBStartCode() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .compressedVideo(withCodec: .h264, transport: .annexB), consumer: consumer)

    stream.consumeSampleBuffer(makeH264SampleBuffer())

    let output = [UInt8](consumer.data())
    XCTAssertFalse(output.isEmpty)
    // Annex-B NAL units are delimited by a 0x00 0x00 0x00 0x01 start code.
    XCTAssertEqual(Array(output.prefix(4)), [0x00, 0x00, 0x00, 0x01])
  }

  func testH264MPEGTSProducesTransportStreamPackets() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .compressedVideo(withCodec: .h264, transport: .mpegts), consumer: consumer)

    stream.consumeSampleBuffer(makeH264SampleBuffer())

    let output = consumer.data()
    XCTAssertFalse(output.isEmpty)
    XCTAssertEqual(output.count % 188, 0, "MPEG-TS output is a whole number of 188-byte packets")
    XCTAssertEqual(output.first, 0x47, "MPEG-TS packets start with the 0x47 sync byte")
  }

  func testMJPEGPassesThroughJPEGBytes() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .mjpeg, consumer: consumer)
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0xFF, 0xD9]

    stream.consumeSampleBuffer(makeJPEGSampleBuffer(bytes: jpeg))

    XCTAssertEqual([UInt8](consumer.data()), jpeg, "MJPEG writes the JPEG block buffer through unframed")
  }

  func testMinicapWritesHeaderThenFrame() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .minicap, consumer: consumer)
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xD9]

    // Frame 0 emits the Minicap global header (sized from the sample's video dimensions), then a
    // length-prefixed JPEG frame.
    stream.consumeSampleBuffer(makeJPEGSampleBuffer(bytes: jpeg, width: 320, height: 240))

    let firstOutput = consumer.data()
    // Header + 4-byte length prefix + JPEG payload; the payload is the trailing bytes.
    XCTAssertGreaterThan(firstOutput.count, jpeg.count + 4)
    XCTAssertEqual(Array(firstOutput.suffix(jpeg.count)), jpeg)

    // A subsequent frame must NOT re-emit the header — only the length-prefixed JPEG.
    let countAfterFirst = firstOutput.count
    stream.consumeSampleBuffer(makeJPEGSampleBuffer(bytes: jpeg, width: 320, height: 240))
    let secondDelta = consumer.data().count - countAfterFirst
    XCTAssertEqual(secondDelta, 4 + jpeg.count, "Only the header is one-shot; later frames are length-prefixed JPEG only")
  }

  func testConsumeWithoutConsumerDoesNotCrash() throws {
    let stream = try makeStream(for: .bgra, consumer: nil)
    // No consumer attached; consuming a frame should be a no-op rather than a crash.
    stream.consumeSampleBuffer(makeBGRASampleBuffer(width: 4, height: 4, fill: 0x00))
  }
}
