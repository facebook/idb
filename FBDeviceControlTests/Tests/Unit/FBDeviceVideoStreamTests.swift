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
import Testing

/// Format → subclass dispatch and each subclass's `consumeSampleBuffer` byte contract. The
/// AVFoundation capture plumbing needs hardware and is not covered here.
@Suite
struct FBDeviceVideoStreamTests {

  // MARK: - Helpers

  private func configuration(_ format: FBVideoStreamFormat) -> FBVideoStreamConfiguration {
    FBVideoStreamConfiguration(format: format, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)
  }

  private func makeStream(for format: FBVideoStreamFormat, consumer: (any FBDataConsumer)?) throws -> FBDeviceVideoStream {
    let streamType = try #require(FBDeviceVideoStream.classForConfiguration(configuration(format)), "Expected a stream type for \(format)")
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

  @Test
  func classForConfigurationResolvesSupportedFormats() {
    #expect((FBDeviceVideoStream.classForConfiguration(configuration(.bgra))) != nil)
    #expect((FBDeviceVideoStream.classForConfiguration(configuration(.mjpeg(encoder: .requireHardware)))) != nil)
    #expect((FBDeviceVideoStream.classForConfiguration(configuration(.minicap))) != nil)
    #expect((FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .h264, transport: .annexB)))) != nil)
    #expect((FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .h264, transport: .mpegts)))) != nil)
  }

  @Test
  func classForConfigurationDistinguishesH264Transports() throws {
    let annexB = try #require(FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .h264, transport: .annexB))))
    let mpegts = try #require(FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .h264, transport: .mpegts))))
    #expect((String(describing: annexB).contains("H264")))
    #expect((String(describing: mpegts).contains("MPEGTS")))
    #expect(!(annexB == mpegts))
  }

  @Test
  func classForConfigurationRejectsHEVC() {
    // HEVC is not supported on the device path.
    #expect((FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .hevc, transport: .annexB)))) == nil)
    #expect((FBDeviceVideoStream.classForConfiguration(configuration(.compressedVideo(withCodec: .hevc, transport: .mpegts)))) == nil)
  }

  // MARK: - consumeSampleBuffer byte contracts

  @Test
  func bGRAWritesRawPixelBytes() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .bgra, consumer: consumer)
    let sampleBuffer = makeBGRASampleBuffer(width: 16, height: 8, fill: 0xAB)
    let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!

    stream.consumeSampleBuffer(sampleBuffer)

    let output = consumer.data()
    #expect(!(output.isEmpty))
    #expect((output.count) == (CVPixelBufferGetDataSize(pixelBuffer)))
    #expect((output.allSatisfy { $0 == 0xAB }), "BGRA bytes should pass through unchanged")
  }

  @Test
  func h264ProducesAnnexBStartCode() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .compressedVideo(withCodec: .h264, transport: .annexB), consumer: consumer)

    stream.consumeSampleBuffer(makeH264SampleBuffer())

    let output = [UInt8](consumer.data())
    #expect(!(output.isEmpty))
    // Annex-B NAL units are delimited by a 0x00 0x00 0x00 0x01 start code.
    #expect((Array(output.prefix(4))) == ([0x00, 0x00, 0x00, 0x01]))
  }

  @Test
  func h264MPEGTSProducesTransportStreamPackets() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .compressedVideo(withCodec: .h264, transport: .mpegts), consumer: consumer)

    stream.consumeSampleBuffer(makeH264SampleBuffer())

    let output = consumer.data()
    #expect(!(output.isEmpty))
    #expect((output.count % 188) == (0), "MPEG-TS output is a whole number of 188-byte packets")
    #expect((output.first) == (0x47), "MPEG-TS packets start with the 0x47 sync byte")
  }

  @Test
  func mJPEGPassesThroughJPEGBytes() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .mjpeg(encoder: .requireHardware), consumer: consumer)
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0xFF, 0xD9]

    stream.consumeSampleBuffer(makeJPEGSampleBuffer(bytes: jpeg))

    #expect(([UInt8](consumer.data())) == (jpeg), "MJPEG writes the JPEG block buffer through unframed")
  }

  @Test
  func minicapWritesHeaderThenFrame() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = try makeStream(for: .minicap, consumer: consumer)
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xD9]

    // Frame 0 emits the Minicap global header (sized from the sample's video dimensions), then a
    // length-prefixed JPEG frame.
    stream.consumeSampleBuffer(makeJPEGSampleBuffer(bytes: jpeg, width: 320, height: 240))

    let firstOutput = consumer.data()
    // Header + 4-byte length prefix + JPEG payload; the payload is the trailing bytes.
    #expect((firstOutput.count) > (jpeg.count + 4))
    #expect((Array(firstOutput.suffix(jpeg.count))) == (jpeg))

    // A subsequent frame must NOT re-emit the header — only the length-prefixed JPEG.
    let countAfterFirst = firstOutput.count
    stream.consumeSampleBuffer(makeJPEGSampleBuffer(bytes: jpeg, width: 320, height: 240))
    let secondDelta = consumer.data().count - countAfterFirst
    #expect((secondDelta) == (4 + jpeg.count), "Only the header is one-shot; later frames are length-prefixed JPEG only")
  }

  @Test
  func consumeWithoutConsumerDoesNotCrash() throws {
    let stream = try makeStream(for: .bgra, consumer: nil)
    stream.consumeSampleBuffer(makeBGRASampleBuffer(width: 4, height: 4, fill: 0x00))
  }
}
