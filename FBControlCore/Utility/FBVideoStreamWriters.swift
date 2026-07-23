/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation

// Faithful Swift translation of the former `FBVideoStream.m` pure-C byte writers:
// H264/HEVC Annex-B, the MPEG-TS muxer (PAT/PMT/PES packetizer, CRC32, ID3 timed
// metadata), the fragmented-MP4 box writer, and the MJPEG/Minicap writers. Behaviour and byte output
// are preserved exactly.

private let MaxAllowedUnprocessedDataCounts: Int = 2

/// Returns true if consumer is ready to process another frame, false if consumer buffered data exceedes allowed limit.
///
/// - Parameter consumer: consumer
/// - Returns: True if next frame should be pushed; False if frame should be dropped
public func checkConsumerBufferLimit(_ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) -> Bool {
  if let asyncConsumer = consumer as? FBDataConsumerAsync {
    let framesInProcess = asyncConsumer.unprocessedDataCount()
    // drop frames if consumer is overflown
    if framesInProcess > MaxAllowedUnprocessedDataCounts {
      logger.log("Consumer is overflown. Number of unsent frames: \(framesInProcess)")
      return false
    }
  }
  return true
}

private let AVCCHeaderLength: Int = 4
private let AnnexBStartCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

public protocol FBEncodedFrameWriter {
  func write(_ sampleBuffer: CMSampleBuffer, to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) throws
}

public protocol FBVideoStreamTimedMetadataWriter {
  func writeTimedMetadata(_ text: String, to consumer: any FBDataConsumer)
}

public struct FBVideoStreamFrameWriters {
  public let frameWriter: any FBEncodedFrameWriter
  public let timedMetadataWriter: (any FBVideoStreamTimedMetadataWriter)?

  public init(frameWriter: any FBEncodedFrameWriter, timedMetadataWriter: (any FBVideoStreamTimedMetadataWriter)?) {
    self.frameWriter = frameWriter
    self.timedMetadataWriter = timedMetadataWriter
  }
}

public extension FBVideoStreamTransport {
  func frameWriters(for codec: FBVideoStreamCodec) -> FBVideoStreamFrameWriters {
    switch self {
    case .fmp4:
      let writer = FBFMP4FrameWriter(codec: codec)
      return FBVideoStreamFrameWriters(frameWriter: writer, timedMetadataWriter: writer)
    case .mpegts:
      let writer = FBMPEGTSFrameWriter(codec: codec)
      return FBVideoStreamFrameWriters(frameWriter: writer, timedMetadataWriter: writer)
    case .annexB:
      return FBVideoStreamFrameWriters(frameWriter: FBAnnexBFrameWriter(codec: codec), timedMetadataWriter: nil)
    }
  }
}

private enum FBVideoStreamWriterError: Error {
  case failedToGetDataPointer(offset: Int, status: OSStatus)
  case failedToGetDataBuffer
  case failedToAccessBlockBufferData(offset: Int, status: OSStatus)
  case failedToReplaceBlockBufferData(offset: Int, status: OSStatus)
  case sampleBufferNotReady
  case failedToGetFormatDescription
  case failedToGetParameterSetCount(codecName: String, status: OSStatus)
  case failedToGetParameterSet(codecName: String, index: Int, status: OSStatus)
  case failedToCopyBlockBufferData(status: OSStatus)
}

extension FBVideoStreamWriterError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case let .failedToGetDataPointer(offset, status):
      return "Failed to get Data Pointer at offset \(offset): \(status)"
    case .failedToGetDataBuffer:
      return "Failed to get data buffer"
    case let .failedToAccessBlockBufferData(offset, status):
      return "Failed to access block buffer data at offset \(offset): \(status)"
    case let .failedToReplaceBlockBufferData(offset, status):
      return "Failed to replace block buffer data at offset \(offset): \(status)"
    case .sampleBufferNotReady:
      return "Sample Buffer is not ready"
    case .failedToGetFormatDescription:
      return "Failed to get format description"
    case let .failedToGetParameterSetCount(codecName, status):
      return "Failed to get \(codecName) parameter set count \(status)"
    case let .failedToGetParameterSet(codecName, index, status):
      return "Failed to get \(codecName) parameter set at index \(index): \(status)"
    case let .failedToCopyBlockBufferData(status):
      return "Failed to copy block buffer data: \(status)"
    }
  }
}

/// Write the contents of a CMBlockBuffer to a data consumer, iterating contiguous segments.
/// Sync consumers receive zero-copy NSData backed by the buffer's memory; async consumers receive a copy.
private func WriteBlockBufferToConsumer(_ blockBuffer: CMBlockBuffer, _ consumer: any FBDataConsumer) throws {
  let dataLength = CMBlockBufferGetDataLength(blockBuffer)
  let isSyncConsumer = consumer is FBDataConsumerSync
  var offset = 0
  while offset < dataLength {
    var dataPointer: UnsafeMutablePointer<CChar>?
    var lengthAtOffset = 0
    let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: offset, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: nil, dataPointerOut: &dataPointer)
    if status != noErr {
      throw FBVideoStreamWriterError.failedToGetDataPointer(offset: offset, status: status)
    }
    guard let dataPointer else {
      throw FBVideoStreamWriterError.failedToGetDataPointer(offset: offset, status: status)
    }
    if isSyncConsumer {
      consumer.consumeData(Data(bytesNoCopy: dataPointer, count: lengthAtOffset, deallocator: .none))
    } else {
      consumer.consumeData(Data(bytes: dataPointer, count: lengthAtOffset))
    }
    offset += lengthAtOffset
  }
}

private func ConvertAVCCToAnnexBInPlace(_ sampleBuffer: CMSampleBuffer) throws {
  guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
    throw FBVideoStreamWriterError.failedToGetDataBuffer
  }
  let dataLength = CMBlockBufferGetDataLength(dataBuffer)

  var offset = 0
  while offset < dataLength - AVCCHeaderLength {
    var nalLengthBuf = [UInt8](repeating: 0, count: AVCCHeaderLength)
    var nalLengthPtr: UnsafeMutablePointer<CChar>?
    var status = nalLengthBuf.withUnsafeMutableBytes { temp -> OSStatus in
      guard let tempBase = temp.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
      return CMBlockBufferAccessDataBytes(dataBuffer, atOffset: offset, length: AVCCHeaderLength, temporaryBlock: tempBase, returnedPointerOut: &nalLengthPtr)
    }
    if status != noErr {
      throw FBVideoStreamWriterError.failedToAccessBlockBufferData(offset: offset, status: status)
    }
    // memcpy(&nalLength, nalLengthPtr, 4) + CFSwapInt32BigToHost: assemble the 4 big-endian bytes.
    var nalLength: UInt32 = 0
    if let nalLengthPtr {
      nalLengthPtr.withMemoryRebound(to: UInt8.self, capacity: AVCCHeaderLength) { bytes in
        nalLength = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
      }
    }
    status = AnnexBStartCode.withUnsafeBytes { ptr -> OSStatus in
      guard let startBase = ptr.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
      return CMBlockBufferReplaceDataBytes(with: startBase, blockBuffer: dataBuffer, offsetIntoDestination: offset, dataLength: AVCCHeaderLength)
    }
    if status != noErr {
      throw FBVideoStreamWriterError.failedToReplaceBlockBufferData(offset: offset, status: status)
    }
    offset += AVCCHeaderLength + Int(nalLength)
  }
}

// H264 and HEVC parameter set getters have identical signatures.
private typealias FBVideoParameterSetGetter = (
  _ formatDescription: CMFormatDescription,
  _ parameterSetIndex: Int,
  _ parameterSetPointerOut: UnsafeMutablePointer<UnsafePointer<UInt8>?>?,
  _ parameterSetSizeOut: UnsafeMutablePointer<Int>?,
  _ parameterSetCountOut: UnsafeMutablePointer<Int>?,
  _ nalUnitHeaderLengthOut: UnsafeMutablePointer<Int32>?
) -> OSStatus

private extension FBVideoStreamCodec {
  var parameterSetGetter: FBVideoParameterSetGetter {
    switch self {
    case .h264:
      return CMVideoFormatDescriptionGetH264ParameterSetAtIndex
    case .hevc:
      return CMVideoFormatDescriptionGetHEVCParameterSetAtIndex
    }
  }

  var displayName: String {
    switch self {
    case .h264:
      return "H264"
    case .hevc:
      return "HEVC"
    }
  }

  var mpegtsStreamType: UInt8 {
    switch self {
    case .h264:
      return H264StreamType
    case .hevc:
      return HEVCStreamType
    }
  }

  var fmp4CompatibleBrand: String {
    switch self {
    case .h264:
      return "mp41"
    case .hevc:
      return "hvc1"
    }
  }

  var fmp4SampleEntryType: String {
    switch self {
    case .h264:
      return "avc1"
    case .hevc:
      return "hvc1"
    }
  }

  var fmp4CodecConfigType: String {
    switch self {
    case .h264:
      return "avcC"
    case .hevc:
      return "hvcC"
    }
  }
}

private func FBVideoSampleBufferIsKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
  guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true), CFArrayGetCount(attachments) != 0 else {
    return false
  }
  let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
  return !CFDictionaryContainsKey(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
}

public struct FBAnnexBFrameWriter: FBEncodedFrameWriter {
  private let codec: FBVideoStreamCodec

  public init(codec: FBVideoStreamCodec) {
    self.codec = codec
  }

  public func write(_ sampleBuffer: CMSampleBuffer, to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) throws {
    if !CMSampleBufferDataIsReady(sampleBuffer) {
      throw FBVideoStreamWriterError.sampleBufferNotReady
    }

    let isKeyFrame = FBVideoSampleBufferIsKeyFrame(sampleBuffer)

    // Convert AVCC length-prefixed NAL units to Annex-B start-code format in place.
    try ConvertAVCCToAnnexBInPlace(sampleBuffer)

    // Get the block buffer for parameter sets and consumer write.
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw FBVideoStreamWriterError.failedToGetDataBuffer
    }

    if isKeyFrame {
      // Keyframes: send parameter sets (SPS, PPS / VPS, SPS, PPS) first, then the converted block buffer.
      guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        throw FBVideoStreamWriterError.failedToGetFormatDescription
      }
      var parameterSetCount = 0
      var status = codec.parameterSetGetter(format, 0, nil, nil, &parameterSetCount, nil)
      if status != noErr {
        throw FBVideoStreamWriterError.failedToGetParameterSetCount(codecName: codec.displayName, status: status)
      }
      for i in 0..<parameterSetCount {
        var paramSize = 0
        var parameterSet: UnsafePointer<UInt8>?
        status = codec.parameterSetGetter(format, i, &parameterSet, &paramSize, nil, nil)
        if status != noErr {
          throw FBVideoStreamWriterError.failedToGetParameterSet(codecName: codec.displayName, index: i, status: status)
        }
        var paramHeader = [UInt8]()
        paramHeader.reserveCapacity(AVCCHeaderLength + paramSize)
        paramHeader.append(contentsOf: AnnexBStartCode)
        if let parameterSet {
          paramHeader.append(contentsOf: UnsafeBufferPointer(start: parameterSet, count: paramSize))
        }
        consumer.consumeData(Data(paramHeader))
      }
    }

    // Send the converted block buffer data.
    try WriteBlockBufferToConsumer(dataBuffer, consumer)
  }
}

// MARK: - MPEG-TS Writer

private let TSPacketSize: Int = 188
private let TSSyncByte: UInt8 = 0x47
private let PATPID: UInt16 = 0x0000
private let PMTPID: UInt16 = 0x0100
private let VideoPID: UInt16 = 0x0101
public let FBMPEGTSMetadataPID: UInt16 = 0x0102
private let HEVCStreamType: UInt8 = 0x24
private let H264StreamType: UInt8 = 0x1B
private let TimedMetadataStreamType: UInt8 = 0x15 // PES private data (ID3)

private let FBMPEGTSCRC32Table: [UInt32] = {
  var table = [UInt32](repeating: 0, count: 256)
  for i in 0..<256 {
    var crc = UInt32(i) << 24
    for _ in 0..<8 {
      if crc & 0x80000000 != 0 {
        crc = (crc << 1) ^ 0x04C11DB7
      } else {
        crc <<= 1
      }
    }
    table[i] = crc
  }
  return table
}()

public func FBMPEGTS_CRC32(_ data: UnsafePointer<UInt8>, _ length: Int) -> UInt32 {
  var crc: UInt32 = 0xFFFFFFFF
  for i in 0..<length {
    crc = (crc << 8) ^ FBMPEGTSCRC32Table[Int(((crc >> 24) ^ UInt32(data[i])) & 0xFF)]
  }
  return crc
}

/// Internal CRC32 over `data[offset..<offset+length]`. Behaviourally identical to
/// `FBMPEGTS_CRC32(ptr, length)` over the same bytes; avoids force-unwrapping a buffer base
/// address at the section-CRC call sites.
private func FBMPEGTSCRC32(_ data: [UInt8], offset: Int, length: Int) -> UInt32 {
  var crc: UInt32 = 0xFFFFFFFF
  for i in 0..<length {
    crc = (crc << 8) ^ FBMPEGTSCRC32Table[Int(((crc >> 24) ^ UInt32(data[offset + i])) & 0xFF)]
  }
  return crc
}

private struct FBMPEGTSSection {
  let startOffset: Int
  let lengthOffset: Int
}

private struct FBMPEGTSPacketWriter {
  private var packet = [UInt8](repeating: 0xFF, count: TSPacketSize)
  private var cursor = 0

  init(pid: UInt16, payloadUnitStart: Bool, continuityCounter: inout UInt8) {
    packet[0] = TSSyncByte
    packet[1] = (payloadUnitStart ? 0x40 : 0x00) | UInt8((pid >> 8) & 0x1F)
    packet[2] = UInt8(pid & 0xFF)
    packet[3] = 0x10 | (continuityCounter & 0x0F)
    continuityCounter &+= 1
    cursor = 4
  }

  mutating func writePointerField(_ value: UInt8 = 0) {
    write8(value)
  }

  mutating func beginSection(tableID: UInt8) -> FBMPEGTSSection {
    let startOffset = cursor
    write8(tableID)
    let lengthOffset = cursor
    write16(0)
    return FBMPEGTSSection(startOffset: startOffset, lengthOffset: lengthOffset)
  }

  mutating func finishSection(_ section: FBMPEGTSSection) {
    let sectionLength = UInt16(cursor - (section.lengthOffset + 2) + 4)
    packet[section.lengthOffset] = 0xB0 | UInt8((sectionLength >> 8) & 0x0F)
    packet[section.lengthOffset + 1] = UInt8(sectionLength & 0xFF)
    write32(FBMPEGTSCRC32(packet, offset: section.startOffset, length: cursor - section.startOffset))
  }

  mutating func write8(_ value: UInt8) {
    packet[cursor] = value
    cursor += 1
  }

  mutating func write16(_ value: UInt16) {
    write8(UInt8((value >> 8) & 0xFF))
    write8(UInt8(value & 0xFF))
  }

  mutating func write32(_ value: UInt32) {
    write8(UInt8((value >> 24) & 0xFF))
    write8(UInt8((value >> 16) & 0xFF))
    write8(UInt8((value >> 8) & 0xFF))
    write8(UInt8(value & 0xFF))
  }

  mutating func writePID(_ pid: UInt16) {
    write8(0xE0 | UInt8((pid >> 8) & 0x1F))
    write8(UInt8(pid & 0xFF))
  }

  mutating func writeLength12(_ length: UInt16) {
    write8(0xF0 | UInt8((length >> 8) & 0x0F))
    write8(UInt8(length & 0xFF))
  }

  func data() -> Data {
    Data(packet)
  }
}

private func FBMPEGTSCreatePESPayloadPacket(
  pid: UInt16,
  payloadUnitStart: Bool,
  continuityCounter: inout UInt8,
  payload: [UInt8],
  payloadOffset: inout Int,
  pcrPTS90k: UInt64?
) -> [UInt8] {
  var packet = [UInt8](repeating: 0xFF, count: TSPacketSize)
  packet[0] = TSSyncByte
  packet[1] = (payloadUnitStart ? 0x40 : 0x00) | UInt8((pid >> 8) & 0x1F)
  packet[2] = UInt8(pid & 0xFF)

  var headerSize = 4
  let remaining = payload.count - payloadOffset

  if let pcrPTS90k {
    packet[3] = 0x30 | (continuityCounter & 0x0F)
    packet[4] = 0x07
    packet[5] = 0x10
    packet[6] = UInt8(truncatingIfNeeded: pcrPTS90k >> 25)
    packet[7] = UInt8(truncatingIfNeeded: pcrPTS90k >> 17)
    packet[8] = UInt8(truncatingIfNeeded: pcrPTS90k >> 9)
    packet[9] = UInt8(truncatingIfNeeded: pcrPTS90k >> 1)
    packet[10] = UInt8(truncatingIfNeeded: ((pcrPTS90k & 1) << 7) | 0x7E)
    packet[11] = 0x00
    headerSize = 12

    let payloadCapacity = TSPacketSize - headerSize
    if remaining < payloadCapacity {
      let stuffingNeeded = payloadCapacity - remaining
      packet[4] = UInt8(0x07 + stuffingNeeded)
      headerSize += stuffingNeeded
    }
  } else {
    let payloadCapacity = TSPacketSize - headerSize
    if remaining < payloadCapacity {
      let stuffingBytes = payloadCapacity - remaining
      packet[3] = 0x30 | (continuityCounter & 0x0F)
      if stuffingBytes == 1 {
        packet[4] = 0x00
        headerSize = 5
      } else {
        packet[4] = UInt8(stuffingBytes - 1)
        packet[5] = 0x00
        headerSize += stuffingBytes
      }
    } else {
      packet[3] = 0x10 | (continuityCounter & 0x0F)
    }
  }

  continuityCounter &+= 1
  let payloadSize = min(TSPacketSize - headerSize, remaining)
  for k in 0..<payloadSize {
    packet[headerSize + k] = payload[payloadOffset + k]
  }
  payloadOffset += payloadSize
  return packet
}

public func FBMPEGTSCreatePATPacket(_ continuityCounter: inout UInt8) -> Data {
  var writer = FBMPEGTSPacketWriter(pid: PATPID, payloadUnitStart: true, continuityCounter: &continuityCounter)
  writer.writePointerField()
  let section = writer.beginSection(tableID: 0x00)
  writer.write16(0x0001)
  writer.write8(0xC1)
  writer.write8(0x00)
  writer.write8(0x00)
  writer.write16(0x0001)
  writer.writePID(PMTPID)
  writer.finishSection(section)
  return writer.data()
}

public func FBMPEGTSCreatePMTPacket(_ continuityCounter: inout UInt8, _ streamType: UInt8) -> Data {
  var writer = FBMPEGTSPacketWriter(pid: PMTPID, payloadUnitStart: true, continuityCounter: &continuityCounter)
  writer.writePointerField()
  let section = writer.beginSection(tableID: 0x02)
  writer.write16(0x0001)
  writer.write8(0xC1)
  writer.write8(0x00)
  writer.write8(0x00)
  writer.writePID(VideoPID)
  writer.writeLength12(0)
  writer.write8(streamType)
  writer.writePID(VideoPID)
  writer.writeLength12(0)
  writer.finishSection(section)
  return writer.data()
}

public func FBMPEGTSPacketizePES(
  _ pesData: Data,
  _ isKeyFrame: Bool,
  _ streamType: UInt8,
  _ pts90k: UInt64,
  _ videoContinuityCounter: inout UInt8,
  _ patContinuityCounter: inout UInt8,
  _ pmtContinuityCounter: inout UInt8,
  _ includeMetadataStream: Bool = false
) -> Data {
  // First packet carries at most 176 bytes (PCR adaptation field uses 8 bytes),
  // remaining packets carry 184 bytes each.
  let firstPayload = pesData.count < 176 ? pesData.count : 176
  let remainingBytes = pesData.count - firstPayload
  let numVideoPackets = 1 + (remainingBytes + 183) / 184
  let totalPackets = (isKeyFrame ? 2 : 0) + numVideoPackets
  var output = Data(capacity: totalPackets * TSPacketSize)

  // Emit PAT + PMT on keyframes for mid-stream join support
  if isKeyFrame {
    output.append(FBMPEGTSCreatePATPacket(&patContinuityCounter))
    output.append(FBMPEGTSCreatePMTPacketWithMetadata(&pmtContinuityCounter, streamType, includeMetadataStream))
  }

  let pesBytes = [UInt8](pesData)
  var pesOffset = 0
  var first = true

  while pesOffset < pesBytes.count {
    let packet = FBMPEGTSCreatePESPayloadPacket(
      pid: VideoPID,
      payloadUnitStart: first,
      continuityCounter: &videoContinuityCounter,
      payload: pesBytes,
      payloadOffset: &pesOffset,
      pcrPTS90k: first ? pts90k : nil
    )
    first = false

    output.append(contentsOf: packet)
  }

  return output
}

public func FBMPEGTSCreatePMTPacketWithMetadata(_ continuityCounter: inout UInt8, _ streamType: UInt8, _ includeMetadataStream: Bool) -> Data {
  if !includeMetadataStream {
    return FBMPEGTSCreatePMTPacket(&continuityCounter, streamType)
  }

  var writer = FBMPEGTSPacketWriter(pid: PMTPID, payloadUnitStart: true, continuityCounter: &continuityCounter)
  writer.writePointerField()
  let section = writer.beginSection(tableID: 0x02)
  writer.write16(0x0001)
  writer.write8(0xC1)
  writer.write8(0x00)
  writer.write8(0x00)
  writer.writePID(VideoPID)
  writer.writeLength12(0)
  writer.write8(streamType)
  writer.writePID(VideoPID)
  writer.writeLength12(0)
  writer.write8(TimedMetadataStreamType)
  writer.writePID(FBMPEGTSMetadataPID)
  writer.writeLength12(0)
  writer.finishSection(section)
  return writer.data()
}

public func FBMPEGTSCreateTimedMetadataPackets(_ text: String, _ pts90k: UInt64, _ metadataContinuityCounter: inout UInt8) -> Data {
  let textData = [UInt8](text.utf8)

  // Build ID3v2.4 tag: header (10 bytes) + TXXX frame
  // TXXX frame: header (10 bytes) + encoding (1) + null description (1) + text
  let txxxPayloadLen = 1 + 1 + textData.count // encoding + null desc + text
  let id3PayloadLen = 10 + txxxPayloadLen // TXXX frame header + payload

  var id3Tag = [UInt8]()
  id3Tag.reserveCapacity(10 + id3PayloadLen)

  // ID3v2 header
  let id3Header: [UInt8] = [
    UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3"),
    0x04, 0x00, // version 2.4
    0x00, // flags
    UInt8((id3PayloadLen >> 21) & 0x7F),
    UInt8((id3PayloadLen >> 14) & 0x7F),
    UInt8((id3PayloadLen >> 7) & 0x7F),
    UInt8(id3PayloadLen & 0x7F),
  ]
  id3Tag.append(contentsOf: id3Header)

  // TXXX frame header
  let txxxHeader: [UInt8] = [
    UInt8(ascii: "T"), UInt8(ascii: "X"), UInt8(ascii: "X"), UInt8(ascii: "X"),
    UInt8((txxxPayloadLen >> 24) & 0xFF),
    UInt8((txxxPayloadLen >> 16) & 0xFF),
    UInt8((txxxPayloadLen >> 8) & 0xFF),
    UInt8(txxxPayloadLen & 0xFF),
    0x00, 0x00, // flags
  ]
  id3Tag.append(contentsOf: txxxHeader)

  // TXXX payload: UTF-8 encoding (0x03), empty description (\0), then text
  id3Tag.append(contentsOf: [0x03, 0x00]) // encoding=UTF-8, null-terminated empty description
  id3Tag.append(contentsOf: textData)

  // Wrap in PES packet (stream_id = 0xBD = private_stream_1)
  let pesHeaderLen = 14 // 9 base + 5 PTS
  let pesTotalLen = pesHeaderLen + id3Tag.count
  let pesPacketLength: UInt16 = (pesTotalLen - 6 <= 0xFFFF) ? UInt16(pesTotalLen - 6) : 0

  var pesPacket = [UInt8]()
  pesPacket.reserveCapacity(pesTotalLen)
  var pesHeader = [UInt8](repeating: 0, count: 14)
  pesHeader[0] = 0x00
  pesHeader[1] = 0x00
  pesHeader[2] = 0x01
  pesHeader[3] = 0xBD // private_stream_1
  pesHeader[4] = UInt8((pesPacketLength >> 8) & 0xFF)
  pesHeader[5] = UInt8(pesPacketLength & 0xFF)
  pesHeader[6] = 0x80 // marker bits
  pesHeader[7] = 0x80 // PTS present, no DTS
  pesHeader[8] = 0x05 // PES header data length (5 bytes for PTS)
  // PTS encoding (indicator nibble 0x2 when PTS only)
  pesHeader[9] = 0x21 | UInt8(truncatingIfNeeded: (pts90k >> 29) & 0x0E)
  pesHeader[10] = UInt8(truncatingIfNeeded: (pts90k >> 22) & 0xFF)
  pesHeader[11] = UInt8(truncatingIfNeeded: ((pts90k >> 14) & 0xFE) | 0x01)
  pesHeader[12] = UInt8(truncatingIfNeeded: (pts90k >> 7) & 0xFF)
  pesHeader[13] = UInt8(truncatingIfNeeded: ((pts90k << 1) & 0xFE) | 0x01)
  pesPacket.append(contentsOf: pesHeader)
  pesPacket.append(contentsOf: id3Tag)

  // Packetize into TS packets on MetadataPID
  let pesBytes = pesPacket
  let numPackets = (pesBytes.count + 183) / 184
  var output = Data(capacity: numPackets * TSPacketSize)

  var pesOffset = 0
  var first = true

  while pesOffset < pesBytes.count {
    let packet = FBMPEGTSCreatePESPayloadPacket(
      pid: FBMPEGTSMetadataPID,
      payloadUnitStart: first,
      continuityCounter: &metadataContinuityCounter,
      payload: pesBytes,
      payloadOffset: &pesOffset,
      pcrPTS90k: nil
    )
    first = false

    output.append(contentsOf: packet)
  }

  return output
}

public final class FBMPEGTSFrameWriter: FBEncodedFrameWriter, FBVideoStreamTimedMetadataWriter {
  private let codec: FBVideoStreamCodec
  private let metadataLock = NSLock()
  private var metadataStreamEnabled = false
  private var metadataContinuityCounter: UInt8 = 0
  private var lastPts90k: UInt64 = 0
  private var videoContinuityCounter: UInt8 = 0
  private var patContinuityCounter: UInt8 = 0
  private var pmtContinuityCounter: UInt8 = 0

  public init(codec: FBVideoStreamCodec) {
    self.codec = codec
  }

  private func enableMetadataStream() {
    metadataLock.lock()
    defer { metadataLock.unlock() }
    metadataStreamEnabled = true
  }

  private func timedMetadataPackets(for text: String) -> Data? {
    metadataLock.lock()
    defer { metadataLock.unlock() }
    guard metadataStreamEnabled else {
      return nil
    }
    return FBMPEGTSCreateTimedMetadataPackets(text, lastPts90k, &metadataContinuityCounter)
  }

  private func recordVideoPTSAndMetadataStreamState(_ pts90k: UInt64) -> Bool {
    metadataLock.lock()
    defer { metadataLock.unlock() }
    lastPts90k = pts90k
    return metadataStreamEnabled
  }

  public func write(_ sampleBuffer: CMSampleBuffer, to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) throws {
    if !CMSampleBufferDataIsReady(sampleBuffer) {
      throw FBVideoStreamWriterError.sampleBufferNotReady
    }

    let isKeyFrame = FBVideoSampleBufferIsKeyFrame(sampleBuffer)

    // Convert AVCC to Annex-B in place before computing sizes.
    // AVCC headers and Annex-B start codes are both 4 bytes so sizes are unchanged.
    try ConvertAVCCToAnnexBInPlace(sampleBuffer)

    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw FBVideoStreamWriterError.failedToGetDataBuffer
    }
    let dataLength = CMBlockBufferGetDataLength(dataBuffer)

    // Compute parameter set sizes upfront (if keyframe) so we can allocate a single buffer.
    var parameterSetSize = 0
    var format: CMFormatDescription?
    var parameterSetCount = 0
    if isKeyFrame {
      format = CMSampleBufferGetFormatDescription(sampleBuffer)
      guard let format else {
        throw FBVideoStreamWriterError.failedToGetFormatDescription
      }
      var status = codec.parameterSetGetter(format, 0, nil, nil, &parameterSetCount, nil)
      if status != noErr {
        throw FBVideoStreamWriterError.failedToGetParameterSetCount(codecName: codec.displayName, status: status)
      }
      for i in 0..<parameterSetCount {
        var paramSize = 0
        status = codec.parameterSetGetter(format, i, nil, &paramSize, nil, nil)
        if status != noErr {
          throw FBVideoStreamWriterError.failedToGetParameterSet(codecName: codec.displayName, index: i, status: status)
        }
        parameterSetSize += AVCCHeaderLength + paramSize
      }
    }

    // Build PES packet in a single allocation: 19-byte header + parameter sets + NAL data.
    // PES header: start code (3) + stream_id (1) + length (2) + flags (2) + header data length (1) = 9
    // With PTS + DTS: add 10 bytes = 19 bytes header
    let pesHeaderLength = 19
    let pesPayloadLength = parameterSetSize + dataLength
    let pesTotalLength = pesHeaderLength + pesPayloadLength
    // PES packet_length field: 0 means unbounded for video, but we'll set it if it fits
    var pesPacketLength: UInt16 = 0
    if pesTotalLength - 6 <= 0xFFFF {
      pesPacketLength = UInt16(pesTotalLength - 6)
    }

    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let pts90k = UInt64(CMTimeGetSeconds(pts) * 90000.0)

    let includeMetadataStream = recordVideoPTSAndMetadataStreamState(pts90k)

    var pesPacket = [UInt8]()
    pesPacket.reserveCapacity(pesTotalLength)

    // PES start code prefix + stream_id (0xE0 = video)
    var pesHeader = [UInt8](repeating: 0, count: 19)
    pesHeader[0] = 0x00
    pesHeader[1] = 0x00
    pesHeader[2] = 0x01
    pesHeader[3] = 0xE0 // stream_id: video
    pesHeader[4] = UInt8((pesPacketLength >> 8) & 0xFF)
    pesHeader[5] = UInt8(pesPacketLength & 0xFF)
    pesHeader[6] = 0x80 // marker bits
    pesHeader[7] = 0xC0 // PTS + DTS present
    pesHeader[8] = 0x0A // PES header data length (10 bytes for PTS + DTS)

    // PTS encoding (33-bit value in 5 bytes, indicator nibble 0x3 when DTS present)
    pesHeader[9] = 0x31 | UInt8(truncatingIfNeeded: (pts90k >> 29) & 0x0E)
    pesHeader[10] = UInt8(truncatingIfNeeded: (pts90k >> 22) & 0xFF)
    pesHeader[11] = UInt8(truncatingIfNeeded: ((pts90k >> 14) & 0xFE) | 0x01)
    pesHeader[12] = UInt8(truncatingIfNeeded: (pts90k >> 7) & 0xFF)
    pesHeader[13] = UInt8(truncatingIfNeeded: ((pts90k << 1) & 0xFE) | 0x01)

    // DTS encoding (33-bit value in 5 bytes, indicator nibble 0x1)
    // DTS == PTS since AllowFrameReordering is NO (decode order = presentation order)
    pesHeader[14] = 0x11 | UInt8(truncatingIfNeeded: (pts90k >> 29) & 0x0E)
    pesHeader[15] = UInt8(truncatingIfNeeded: (pts90k >> 22) & 0xFF)
    pesHeader[16] = UInt8(truncatingIfNeeded: ((pts90k >> 14) & 0xFE) | 0x01)
    pesHeader[17] = UInt8(truncatingIfNeeded: (pts90k >> 7) & 0xFF)
    pesHeader[18] = UInt8(truncatingIfNeeded: ((pts90k << 1) & 0xFE) | 0x01)

    pesPacket.append(contentsOf: pesHeader)

    // Append parameter sets for keyframes (start code + set bytes for each)
    if isKeyFrame, let format {
      for i in 0..<parameterSetCount {
        var paramSize = 0
        var parameterSet: UnsafePointer<UInt8>?
        _ = codec.parameterSetGetter(format, i, &parameterSet, &paramSize, nil, nil)
        pesPacket.append(contentsOf: AnnexBStartCode)
        if let parameterSet {
          pesPacket.append(contentsOf: UnsafeBufferPointer(start: parameterSet, count: paramSize))
        }
      }
    }

    // Copy NAL data directly from CMBlockBuffer into pesPacket (handles non-contiguous buffers)
    let nalDestOffset = pesPacket.count
    pesPacket.append(contentsOf: [UInt8](repeating: 0, count: dataLength))
    let copyStatus = pesPacket.withUnsafeMutableBufferPointer { ptr -> OSStatus in
      guard let nalDest = ptr.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
      return CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: dataLength, destination: nalDest + nalDestOffset)
    }
    if copyStatus != noErr {
      throw FBVideoStreamWriterError.failedToCopyBlockBufferData(status: copyStatus)
    }

    // Packetize into MPEG-TS and write to consumer
    let tsData = FBMPEGTSPacketizePES(
      Data(pesPacket),
      isKeyFrame,
      codec.mpegtsStreamType,
      pts90k,
      &videoContinuityCounter,
      &patContinuityCounter,
      &pmtContinuityCounter,
      includeMetadataStream
    )
    consumer.consumeData(tsData)
  }

  public func writeTimedMetadata(_ text: String, to consumer: any FBDataConsumer) {
    enableMetadataStream()
    guard let packets = timedMetadataPackets(for: text) else {
      return
    }
    consumer.consumeData(packets)
  }
}

public struct FBMJPEGFrameWriter {
  public init() {}

  public func write(_ jpegDataBuffer: CMBlockBuffer, to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) throws {
    try WriteBlockBufferToConsumer(jpegDataBuffer, consumer)
  }
}

public struct FBMinicapFrameWriter {
  public init() {}

  public func write(_ jpegDataBuffer: CMBlockBuffer, to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) throws {
    let dataLength = CMBlockBufferGetDataLength(jpegDataBuffer)
    var imageLength = UInt32(dataLength).littleEndian
    let lengthData = Data(bytes: &imageLength, count: MemoryLayout<UInt32>.size)
    consumer.consumeData(lengthData)

    try WriteBlockBufferToConsumer(jpegDataBuffer, consumer)
  }

  // MinicapHeader is built byte-by-byte (24 bytes, all little-endian) rather than relying
  // on Swift struct layout, matching the `#pragma pack(push, 1)` C struct.
  // https://github.com/openstf/minicap#usage
  public func writeHeader(width: UInt32, height: UInt32, to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) {
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

// MARK: - Fragmented MP4 (fMP4) Writer

private struct FBFMP4BoxWriter {
  private(set) var data: [UInt8]

  init(capacity: Int = 0) {
    data = []
    data.reserveCapacity(capacity)
  }

  var count: Int {
    data.count
  }

  mutating func write8(_ value: UInt8) {
    data.append(value)
  }

  mutating func write16(_ value: UInt16) {
    let be = value.bigEndian
    withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
  }

  mutating func write32(_ value: UInt32) {
    let be = value.bigEndian
    withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
  }

  mutating func write64(_ value: UInt64) {
    let be = value.bigEndian
    withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
  }

  mutating func beginBox(_ type: String) -> Int {
    let offset = data.count
    write32(0)
    writeBytes(type)
    return offset
  }

  mutating func endBox(_ sizeOffset: Int) {
    write32(UInt32(data.count - sizeOffset), at: sizeOffset)
  }

  mutating func writeFullBoxHeader(version: UInt8, flags: UInt32) {
    write32((UInt32(version) << 24) | (flags & 0x00FFFFFF))
  }

  mutating func writeZeros(_ count: Int) {
    assert(count <= 64, "Zero count greater than 64")
    data.append(contentsOf: [UInt8](repeating: 0, count: count))
  }

  mutating func writeBytes(_ string: String) {
    data.append(contentsOf: string.utf8)
  }

  mutating func append(_ bytes: [UInt8]) {
    data.append(contentsOf: bytes)
  }

  mutating func append(_ data: Data) {
    self.data.append(contentsOf: data)
  }

  mutating func append(_ bytes: UnsafeBufferPointer<UInt8>) {
    data.append(contentsOf: bytes)
  }

  mutating func write32(_ value: UInt32, at offset: Int) {
    let be = value.bigEndian
    withUnsafeBytes(of: be) { bytes in
      for k in 0..<4 {
        data[offset + k] = bytes[k]
      }
    }
  }
}

private func FBFMP4GetCodecConfigAtom(_ formatDescription: CMFormatDescription, _ codec: FBVideoStreamCodec) -> [UInt8]? {
  if let atoms = CMFormatDescriptionGetExtension(formatDescription, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any] {
    if let configData = atoms[codec.fmp4CodecConfigType] as? Data {
      return [UInt8](configData)
    }
  }
  // Fallback: build avcC/hvcC manually from parameter sets.
  var writer = FBFMP4BoxWriter()
  switch codec {
  case .h264:
    var sps: UnsafePointer<UInt8>?
    var spsSize = 0
    var paramCount = 0
    let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: &sps, parameterSetSizeOut: &spsSize, parameterSetCountOut: &paramCount, nalUnitHeaderLengthOut: nil)
    guard status == noErr, spsSize >= 4, let sps else {
      return nil
    }

    var pps: UnsafePointer<UInt8>?
    var ppsSize = 0
    if paramCount > 1 {
      CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 1, parameterSetPointerOut: &pps, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
    }

    writer.write8(1)
    writer.write8(sps[1])
    writer.write8(sps[2])
    writer.write8(sps[3])
    writer.write8(0xFF)
    writer.write8(0xE1)
    writer.write16(UInt16(spsSize))
    writer.append(UnsafeBufferPointer(start: sps, count: spsSize))
    writer.write8(pps != nil ? 1 : 0)
    if let pps {
      writer.write16(UInt16(ppsSize))
      writer.append(UnsafeBufferPointer(start: pps, count: ppsSize))
    }
  case .hevc:
    var paramCount = 0
    let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &paramCount, nalUnitHeaderLengthOut: nil)
    if status != noErr {
      return nil
    }

    var paramSets = [[UInt8]]()
    var paramTypes = [UInt8]()
    for i in 0..<paramCount {
      var ps: UnsafePointer<UInt8>?
      var psSize = 0
      CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDescription, parameterSetIndex: i, parameterSetPointerOut: &ps, parameterSetSizeOut: &psSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
      if let ps, psSize > 0 {
        paramSets.append([UInt8](UnsafeBufferPointer(start: ps, count: psSize)))
        let nalType = (ps[0] >> 1) & 0x3F
        paramTypes.append(nalType)
      }
    }

    writer.write8(1)
    writer.write8(0)
    writer.write32(0)
    writer.write16(0)
    writer.write32(0)
    writer.write8(0)
    writer.write16(0xF000)
    writer.write8(0xFC)
    writer.write8(0xFC)
    writer.write8(0xF8)
    writer.write8(0xF8)
    writer.write16(0)
    writer.write8(0x0F)

    // Group parameter sets by NAL type, preserving first-seen type order
    // (NSMutableDictionary enumeration order is unspecified in ObjC, but the keys
    // here are small distinct integers; preserving insertion order is a faithful and
    // deterministic interpretation).
    var groupedOrder = [UInt8]()
    var grouped = [UInt8: [[UInt8]]]()
    for i in 0..<paramSets.count {
      let type = paramTypes[i]
      if grouped[type] == nil {
        grouped[type] = []
        groupedOrder.append(type)
      }
      grouped[type]?.append(paramSets[i])
    }

    writer.write8(UInt8(groupedOrder.count))
    for nalType in groupedOrder {
      let sets = grouped[nalType] ?? []
      writer.write8(nalType & 0x3F)
      writer.write16(UInt16(sets.count))
      for set in sets {
        writer.write16(UInt16(set.count))
        writer.append(set)
      }
    }
  }
  return writer.data
}

private func FBFMP4CreateFtypBox(_ codec: FBVideoStreamCodec) -> [UInt8] {
  var writer = FBFMP4BoxWriter(capacity: 24)
  let off = writer.beginBox("ftyp")
  writer.writeBytes("isom")
  writer.write32(0x200)
  writer.writeBytes("isom")
  writer.writeBytes("iso6")
  writer.writeBytes(codec.fmp4CompatibleBrand)
  writer.endBox(off)
  return writer.data
}

private func FBFMP4CreateMoovBox(_ formatDescription: CMFormatDescription, _ codec: FBVideoStreamCodec, _ width: UInt32, _ height: UInt32, _ timescale: UInt32) -> [UInt8] {
  var writer = FBFMP4BoxWriter(capacity: 512)

  let codecConfig = FBFMP4GetCodecConfigAtom(formatDescription, codec)

  let moovOff = writer.beginBox("moov")

  // mvhd
  do {
    let off = writer.beginBox("mvhd")
    writer.writeFullBoxHeader(version: 0, flags: 0)
    writer.write32(0)
    writer.write32(0)
    writer.write32(timescale)
    writer.write32(0)
    writer.write32(0x00010000)
    writer.write16(0x0100)
    writer.writeZeros(10)
    let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
    for i in 0..<9 {
      writer.write32(matrix[i])
    }
    writer.writeZeros(24)
    writer.write32(2)
    writer.endBox(off)
  }

  // trak
  do {
    let trakOff = writer.beginBox("trak")

    // tkhd
    do {
      let off = writer.beginBox("tkhd")
      writer.writeFullBoxHeader(version: 0, flags: 0x03)
      writer.write32(0)
      writer.write32(0)
      writer.write32(1)
      writer.write32(0)
      writer.write32(0)
      writer.writeZeros(8)
      writer.write16(0)
      writer.write16(0)
      writer.write16(0)
      writer.write16(0)
      let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
      for i in 0..<9 {
        writer.write32(matrix[i])
      }
      writer.write32(width << 16)
      writer.write32(height << 16)
      writer.endBox(off)
    }

    // mdia
    do {
      let mdiaOff = writer.beginBox("mdia")

      // mdhd
      do {
        let off = writer.beginBox("mdhd")
        writer.writeFullBoxHeader(version: 0, flags: 0)
        writer.write32(0)
        writer.write32(0)
        writer.write32(timescale)
        writer.write32(0)
        writer.write16(0x55C4)
        writer.write16(0)
        writer.endBox(off)
      }

      // hdlr
      do {
        let off = writer.beginBox("hdlr")
        writer.writeFullBoxHeader(version: 0, flags: 0)
        writer.write32(0)
        writer.writeBytes("vide")
        writer.writeZeros(12)
        let name = "VideoHandler"
        writer.writeBytes(name)
        writer.write8(0) // null terminator (strlen(name) + 1)
        writer.endBox(off)
      }

      // minf
      do {
        let minfOff = writer.beginBox("minf")

        // vmhd
        do {
          let off = writer.beginBox("vmhd")
          writer.writeFullBoxHeader(version: 0, flags: 1)
          writer.write16(0)
          writer.writeZeros(6)
          writer.endBox(off)
        }

        // dinf → dref → url
        do {
          let dinfOff = writer.beginBox("dinf")
          let drefOff = writer.beginBox("dref")
          writer.writeFullBoxHeader(version: 0, flags: 0)
          writer.write32(1)
          let urlOff = writer.beginBox("url ")
          writer.writeFullBoxHeader(version: 0, flags: 1)
          writer.endBox(urlOff)
          writer.endBox(drefOff)
          writer.endBox(dinfOff)
        }

        // stbl
        do {
          let stblOff = writer.beginBox("stbl")

          // stsd
          do {
            let stsdOff = writer.beginBox("stsd")
            writer.writeFullBoxHeader(version: 0, flags: 0)
            writer.write32(1)

            // Visual sample entry (avc1 or hvc1)
            do {
              let entryOff = writer.beginBox(codec.fmp4SampleEntryType)
              writer.writeZeros(6)
              writer.write16(1)
              writer.writeZeros(16)
              writer.write16(UInt16(width))
              writer.write16(UInt16(height))
              writer.write32(0x00480000)
              writer.write32(0x00480000)
              writer.write32(0)
              writer.write16(1)
              writer.writeZeros(32)
              writer.write16(0x0018)
              writer.write16(0xFFFF)

              if let codecConfig {
                let ccOff = writer.beginBox(codec.fmp4CodecConfigType)
                writer.append(codecConfig)
                writer.endBox(ccOff)
              }

              writer.endBox(entryOff)
            }

            writer.endBox(stsdOff)
          }

          // Empty required boxes
          do {
            var off = writer.beginBox("stts")
            writer.writeFullBoxHeader(version: 0, flags: 0)
            writer.write32(0)
            writer.endBox(off)

            off = writer.beginBox("stsc")
            writer.writeFullBoxHeader(version: 0, flags: 0)
            writer.write32(0)
            writer.endBox(off)

            off = writer.beginBox("stsz")
            writer.writeFullBoxHeader(version: 0, flags: 0)
            writer.write32(0)
            writer.write32(0)
            writer.endBox(off)

            off = writer.beginBox("stco")
            writer.writeFullBoxHeader(version: 0, flags: 0)
            writer.write32(0)
            writer.endBox(off)
          }

          writer.endBox(stblOff)
        }

        writer.endBox(minfOff)
      }

      writer.endBox(mdiaOff)
    }

    writer.endBox(trakOff)
  }

  // mvex
  do {
    let mvexOff = writer.beginBox("mvex")
    let trexOff = writer.beginBox("trex")
    writer.writeFullBoxHeader(version: 0, flags: 0)
    writer.write32(1)
    writer.write32(1)
    writer.write32(0)
    writer.write32(0)
    writer.write32(0)
    writer.endBox(trexOff)
    writer.endBox(mvexOff)
  }

  writer.endBox(moovOff)
  return writer.data
}

// Build the moof + mdat header for a single-sample fragment.
// The sample data itself is NOT included — the caller emits it separately
// to avoid a redundant copy of the (potentially large) video frame payload.
// The returned Data ends just after the mdat box header; the caller must
// append exactly `sampleSize` bytes of sample data, then the fragment is complete.
private func FBFMP4CreateFragmentHeader(_ sequenceNumber: UInt32, _ baseDecodeTime: UInt64, _ duration: UInt32, _ sampleSize: UInt32, _ isKeyFrame: Bool) -> [UInt8] {
  let trunFlags: UInt32 = 0x000701
  // trun: header(12) + data_offset(4) + 1 sample entry (duration(4) + size(4) + flags(4))
  let trunSize = 12 + 4 + 12
  let moofSize = 8 + 16 + 8 + 16 + 20 + trunSize
  let mdatHeaderSize = 8

  var writer = FBFMP4BoxWriter(capacity: moofSize + mdatHeaderSize)

  let moofOff = writer.beginBox("moof")

  // mfhd
  do {
    let off = writer.beginBox("mfhd")
    writer.writeFullBoxHeader(version: 0, flags: 0)
    writer.write32(sequenceNumber)
    writer.endBox(off)
  }

  // traf
  do {
    let trafOff = writer.beginBox("traf")

    // tfhd
    do {
      let off = writer.beginBox("tfhd")
      writer.writeFullBoxHeader(version: 0, flags: 0x020000)
      writer.write32(1)
      writer.endBox(off)
    }

    // tfdt
    do {
      let off = writer.beginBox("tfdt")
      writer.writeFullBoxHeader(version: 1, flags: 0)
      writer.write64(baseDecodeTime)
      writer.endBox(off)
    }

    // trun — single sample
    do {
      _ = writer.beginBox("trun")
      writer.writeFullBoxHeader(version: 0, flags: trunFlags)
      writer.write32(1) // sample_count = 1
      writer.write32(0) // placeholder for data_offset (patched below)
      writer.write32(duration)
      writer.write32(sampleSize)
      writer.write32(isKeyFrame ? 0x02000000 : 0x01010000)
    }

    writer.endBox(trafOff)
  }

  writer.endBox(moofOff)

  // Patch data_offset: distance from moof start to first sample byte in mdat.
  let actualMoofSize = UInt32(writer.count - moofOff)
  let dataOffset = actualMoofSize + UInt32(mdatHeaderSize)
  // dataOffsetPos = moofOff + moof_header(8) + mfhd(16) + traf_header(8) + tfhd(16) + tfdt(20) + trun_header(12) + sample_count(4)
  let patchPos = moofOff + 8 + 16 + 8 + 16 + 20 + 12 + 4
  writer.write32(dataOffset, at: patchPos)

  // mdat header only — caller appends sample data.
  writer.write32(UInt32(mdatHeaderSize) + sampleSize)
  writer.writeBytes("mdat")

  return writer.data
}

public final class FBFMP4FrameWriter: FBEncodedFrameWriter, FBVideoStreamTimedMetadataWriter {
  private let codec: FBVideoStreamCodec
  private(set) var initWritten: Bool
  private(set) var sequenceNumber: UInt32
  private var baseDecodeTime: UInt64
  var lastPts90k: UInt64

  public init(codec: FBVideoStreamCodec) {
    self.codec = codec
    self.initWritten = false
    self.sequenceNumber = 0
    self.baseDecodeTime = 0
    self.lastPts90k = 0
  }

  public func write(_ sampleBuffer: CMSampleBuffer, to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) throws {
    if !CMSampleBufferDataIsReady(sampleBuffer) {
      throw FBVideoStreamWriterError.sampleBufferNotReady
    }

    let isKeyFrame = FBVideoSampleBufferIsKeyFrame(sampleBuffer)

    // Extract PTS.
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let pts90k = UInt64(CMTimeGetSeconds(pts) * 90000.0)
    let prevPts90k = lastPts90k
    lastPts90k = pts90k

    // On first keyframe: emit init segment (ftyp + moov).
    if !initWritten {
      if !isKeyFrame {
        return // Drop frames before first keyframe.
      }

      guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        throw FBVideoStreamWriterError.failedToGetFormatDescription
      }
      let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)

      let ftyp = FBFMP4CreateFtypBox(codec)
      let moov = FBFMP4CreateMoovBox(formatDesc, codec, UInt32(dims.width), UInt32(dims.height), 90000)

      consumer.consumeData(Data(ftyp))
      consumer.consumeData(Data(moov))

      initWritten = true
      baseDecodeTime = pts90k
      logger.log("fMP4 init segment written (\(dims.width)x\(dims.height), \(codec.displayName))")
    }

    // Compute duration.
    let duration90k: UInt32
    let sampleDuration = CMSampleBufferGetDuration(sampleBuffer)
    if CMTIME_IS_VALID(sampleDuration) && CMTimeGetSeconds(sampleDuration) > 0 {
      duration90k = UInt32(CMTimeGetSeconds(sampleDuration) * 90000.0)
    } else if prevPts90k > 0 && pts90k > prevPts90k {
      duration90k = UInt32(pts90k - prevPts90k)
    } else {
      duration90k = 3000 // ~33ms at 30fps fallback
    }

    // Get AVCC NAL data (do NOT convert to Annex-B).
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw FBVideoStreamWriterError.failedToGetDataBuffer
    }
    let dataLength = CMBlockBufferGetDataLength(dataBuffer)

    // Emit moof + mdat header, then sample data — single copy only.
    sequenceNumber += 1
    let header = FBFMP4CreateFragmentHeader(sequenceNumber, baseDecodeTime, duration90k, UInt32(dataLength), isKeyFrame)
    consumer.consumeData(Data(header))

    // Try zero-copy via CMBlockBufferGetDataPointer (works when buffer is contiguous).
    var dataPointer: UnsafeMutablePointer<CChar>?
    var lengthAtOffset = 0
    let ptrStatus = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: nil, dataPointerOut: &dataPointer)
    if ptrStatus == noErr, let dataPointer, lengthAtOffset >= dataLength {
      consumer.consumeData(Data(bytesNoCopy: dataPointer, count: dataLength, deallocator: .none))
    } else {
      // Fallback: copy when the block buffer is non-contiguous.
      var sampleData = Data(count: dataLength)
      let copyStatus = sampleData.withUnsafeMutableBytes { ptr -> OSStatus in
        guard let dest = ptr.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
        return CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: dataLength, destination: dest)
      }
      if copyStatus != noErr {
        throw FBVideoStreamWriterError.failedToCopyBlockBufferData(status: copyStatus)
      }
      consumer.consumeData(sampleData)
    }

    baseDecodeTime += UInt64(duration90k)
  }

  public func writeTimedMetadata(_ text: String, to consumer: any FBDataConsumer) {
    consumer.consumeData(FBFMP4CreateEmsgBox(lastPts90k, text))
  }
}

private func FBFMP4CreateEmsgBox(_ presentationTime90k: UInt64, _ text: String) -> Data {
  let textData = [UInt8](text.utf8)

  var writer = FBFMP4BoxWriter(capacity: 64 + textData.count)

  let off = writer.beginBox("emsg")
  writer.writeFullBoxHeader(version: 1, flags: 0)
  writer.write32(90000)
  writer.write64(presentationTime90k)
  writer.write32(0)
  writer.write32(0)

  let scheme = "urn:sime2e:chapter"
  writer.writeBytes(scheme)
  writer.write8(0) // null terminator (strlen(scheme) + 1)
  writer.write8(0) // empty value string
  writer.append(textData)

  writer.endBox(off)

  return Data(writer.data)
}
