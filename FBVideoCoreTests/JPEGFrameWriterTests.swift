/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBControlCore
@testable import FBVideoCore
import Foundation
import Testing

/// The MJPEG and Minicap byte contracts.
@Suite
struct JPEGFrameWriterTests {

  // MARK: - Minicap Header

  @Test
  func writeMinicapHeader() {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MinicapFrameWriter()

    writer.writeHeader(width: 1920, height: 1080, to: consumer, logger: logger)

    let output = consumer.data()
    #expect(output.count == 24)

    let bytes = Array(output)

    // version = 1
    #expect(bytes[0] == 1)
    // headerSize = 24
    #expect(bytes[1] == 24)

    // displayWidth = 1920 in little-endian at offset 6
    var width: UInt32 = 0
    withUnsafeMutableBytes(of: &width) { widthPtr in
      widthPtr.copyBytes(from: bytes[6..<10])
    }
    width = UInt32(littleEndian: width)
    #expect(width == 1920)

    // displayHeight = 1080 in little-endian at offset 10
    var height: UInt32 = 0
    withUnsafeMutableBytes(of: &height) { heightPtr in
      heightPtr.copyBytes(from: bytes[10..<14])
    }
    height = UInt32(littleEndian: height)
    #expect(height == 1080)
  }

  // MARK: - MJPEG / Minicap Frame Writers

  @Test
  func mjpegFrameWriterWritesRawBytes() {
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0xFF, 0xD9]
    let blockBuffer = makeBlockBuffer(jpeg)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MJPEGFrameWriter()

    #expect(throws: Never.self) { try writer.write(blockBuffer, to: consumer, logger: logger) }

    #expect(consumer.data() == Data(jpeg))
  }

  @Test
  func minicapFrameWriterPrependsLittleEndianLength() {
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xD9]
    let blockBuffer = makeBlockBuffer(jpeg)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MinicapFrameWriter()

    #expect(throws: Never.self) { try writer.write(blockBuffer, to: consumer, logger: logger) }

    let output = consumer.data()
    #expect(output.count == 4 + jpeg.count)

    var length: UInt32 = 0
    withUnsafeMutableBytes(of: &length) { $0.copyBytes(from: output.subdata(in: 0..<4)) }
    #expect(UInt32(littleEndian: length) == UInt32(jpeg.count))
    #expect(output.subdata(in: 4..<output.count) == Data(jpeg))
  }

  // MARK: - As EncodedFrameWriters

  @Test
  func minicapWritesTheHeaderOnceFromTheFirstSample() throws {
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xD9]
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MinicapFrameWriter()

    try writer.write(makeJPEGSampleBuffer(bytes: jpeg, width: 320, height: 240), to: consumer, logger: logger)
    let afterFirst = consumer.data().count
    #expect(afterFirst == 24 + 4 + jpeg.count)
    try writer.write(makeJPEGSampleBuffer(bytes: jpeg, width: 320, height: 240), to: consumer, logger: logger)
    #expect(consumer.data().count - afterFirst == 4 + jpeg.count, "only the first frame carries the header")
  }

  @Test
  func mjpegWritesTheSampleBytesThrough() throws {
    let jpeg: [UInt8] = [0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]
    let consumer = FBDataBuffer.accumulatingBuffer()
    try MJPEGFrameWriter().write(makeJPEGSampleBuffer(bytes: jpeg, width: 8, height: 8), to: consumer, logger: ControlCoreLoggerDouble())
    #expect(consumer.data() == Data(jpeg))
  }

  @Test
  func bgraWritesThePixelBytesThrough() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let sampleBuffer = makeBGRASampleBuffer(width: 16, height: 8, fill: 0xAB)
    try BGRAFrameWriter().write(sampleBuffer, to: consumer, logger: ControlCoreLoggerDouble())
    let pixelBuffer = try #require(CMSampleBufferGetImageBuffer(sampleBuffer))
    #expect(consumer.data().count == CVPixelBufferGetDataSize(pixelBuffer))
    #expect(consumer.data().allSatisfy { $0 == 0xAB })
  }

  @Test
  func everyFormatHasFrameWriters() {
    #expect(VideoStreamFormat.mjpeg(encoder: .requireHardware).frameWriters().frameWriter is MJPEGFrameWriter)
    #expect(VideoStreamFormat.minicap.frameWriters().frameWriter is MinicapFrameWriter)
    #expect(VideoStreamFormat.bgra.frameWriters().frameWriter is BGRAFrameWriter)
    #expect(VideoStreamFormat.compressedVideo(withCodec: .h264, transport: .mpegts).frameWriters().frameWriter is MPEGTSFrameWriter)
    #expect(VideoStreamFormat.minicap.frameWriters().timedMetadataWriter == nil)
  }
}
