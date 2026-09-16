/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBControlCore
import XCTest

/// The MJPEG and Minicap byte contracts.
final class JPEGFrameWriterTests: XCTestCase {

  // MARK: - Minicap Header

  func testWriteMinicapHeader() {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MinicapFrameWriter()

    writer.writeHeader(width: 1920, height: 1080, to: consumer, logger: logger)

    let output = consumer.data()
    XCTAssertEqual(output.count, 24)

    let bytes = Array(output)

    // version = 1
    XCTAssertEqual(bytes[0], 1)
    // headerSize = 24
    XCTAssertEqual(bytes[1], 24)

    // displayWidth = 1920 in little-endian at offset 6
    var width: UInt32 = 0
    withUnsafeMutableBytes(of: &width) { widthPtr in
      widthPtr.copyBytes(from: bytes[6..<10])
    }
    width = UInt32(littleEndian: width)
    XCTAssertEqual(width, 1920)

    // displayHeight = 1080 in little-endian at offset 10
    var height: UInt32 = 0
    withUnsafeMutableBytes(of: &height) { heightPtr in
      heightPtr.copyBytes(from: bytes[10..<14])
    }
    height = UInt32(littleEndian: height)
    XCTAssertEqual(height, 1080)
  }

  // MARK: - MJPEG / Minicap Frame Writers

  func testMJPEGFrameWriterWritesRawBytes() {
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0xFF, 0xD9]
    let blockBuffer = makeBlockBuffer(jpeg)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MJPEGFrameWriter()

    XCTAssertNoThrow(try writer.write(blockBuffer, to: consumer, logger: logger))

    XCTAssertEqual(consumer.data(), Data(jpeg))
  }

  func testMinicapFrameWriterPrependsLittleEndianLength() {
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xD9]
    let blockBuffer = makeBlockBuffer(jpeg)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MinicapFrameWriter()

    XCTAssertNoThrow(try writer.write(blockBuffer, to: consumer, logger: logger))

    let output = consumer.data()
    XCTAssertEqual(output.count, 4 + jpeg.count)

    var length: UInt32 = 0
    withUnsafeMutableBytes(of: &length) { $0.copyBytes(from: output.subdata(in: 0..<4)) }
    XCTAssertEqual(UInt32(littleEndian: length), UInt32(jpeg.count))
    XCTAssertEqual(output.subdata(in: 4..<output.count), Data(jpeg))
  }
}
