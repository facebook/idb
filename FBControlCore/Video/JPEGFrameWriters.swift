/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation

public struct MJPEGFrameWriter {
  public init() {}

  public func write(_ jpegDataBuffer: CMBlockBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) throws {
    try WriteBlockBufferToConsumer(jpegDataBuffer, consumer)
  }
}

public struct MinicapFrameWriter {
  public init() {}

  public func write(_ jpegDataBuffer: CMBlockBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) throws {
    let dataLength = CMBlockBufferGetDataLength(jpegDataBuffer)
    var imageLength = UInt32(dataLength).littleEndian
    let lengthData = Data(bytes: &imageLength, count: MemoryLayout<UInt32>.size)
    consumer.consumeData(lengthData)

    try WriteBlockBufferToConsumer(jpegDataBuffer, consumer)
  }

  // MinicapHeader is built byte-by-byte (24 bytes, all little-endian) rather than relying
  // on Swift struct layout, matching the `#pragma pack(push, 1)` C struct.
  // https://github.com/openstf/minicap#usage
  public func writeHeader(width: UInt32, height: UInt32, to consumer: any DataConsumer, logger: any ControlCoreLogger) {
    let headerSize: UInt8 = 24
    let pid = UInt32(bitPattern: ProcessInfo.processInfo.processIdentifier).littleEndian
    let displayWidth = width.littleEndian
    let displayHeight = height.littleEndian
    let virtualDisplayWidth = width.littleEndian
    let virtualDisplayHeight = height.littleEndian

    var header = [UInt8]()
    header.reserveCapacity(Int(headerSize))
    header.append(1) // version = 1
    header.append(headerSize) // headerSize = 24
    withUnsafeBytes(of: pid) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: displayWidth) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: displayHeight) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: virtualDisplayWidth) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: virtualDisplayHeight) { header.append(contentsOf: $0) }
    header.append(0) // displayOrientation
    header.append(0) // quirks

    consumer.consumeData(Data(header))
  }
}
