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
// metadata), the fragmented-MP4 box writer + `FBFMP4MuxerContext`, and the
// MJPEG/Minicap writers. Behaviour and byte output are preserved exactly.

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
  case fmp4WriterCalledWithoutContext
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
    case .fmp4WriterCalledWithoutContext:
      return "fMP4 writer called without context"
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

private func WriteCodecFrameToAnnexBStream(_ sampleBuffer: CMSampleBuffer, _ paramSetGetter: FBVideoParameterSetGetter, _ codecName: String, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  if !CMSampleBufferDataIsReady(sampleBuffer) {
    throw FBVideoStreamWriterError.sampleBufferNotReady
  }

  var isKeyFrame = false
  if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true), CFArrayGetCount(attachments) != 0 {
    let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
    isKeyFrame = !CFDictionaryContainsKey(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
  }

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
    var status = paramSetGetter(format, 0, nil, nil, &parameterSetCount, nil)
    if status != noErr {
      throw FBVideoStreamWriterError.failedToGetParameterSetCount(codecName: codecName, status: status)
    }
    for i in 0..<parameterSetCount {
      var paramSize = 0
      var parameterSet: UnsafePointer<UInt8>?
      status = paramSetGetter(format, i, &parameterSet, &paramSize, nil, nil)
      if status != noErr {
        throw FBVideoStreamWriterError.failedToGetParameterSet(codecName: codecName, index: i, status: status)
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

public func WriteFrameToAnnexBStream(_ sampleBuffer: CMSampleBuffer, _ context: Any?, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  try WriteCodecFrameToAnnexBStream(sampleBuffer, CMVideoFormatDescriptionGetH264ParameterSetAtIndex, "H264", consumer, logger)
}

public func WriteHEVCFrameToAnnexBStream(_ sampleBuffer: CMSampleBuffer, _ context: Any?, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  try WriteCodecFrameToAnnexBStream(sampleBuffer, CMVideoFormatDescriptionGetHEVCParameterSetAtIndex, "HEVC", consumer, logger)
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

public func FBMPEGTSCreatePATPacket(_ continuityCounter: inout UInt8) -> Data {
  var packet = [UInt8](repeating: 0xFF, count: TSPacketSize)

  // TS header
  packet[0] = TSSyncByte
  packet[1] = 0x40 | UInt8((PATPID >> 8) & 0x1F) // payload_unit_start=1
  packet[2] = UInt8(PATPID & 0xFF)
  packet[3] = 0x10 | (continuityCounter & 0x0F) // no adaptation, payload only
  continuityCounter &+= 1

  // Pointer field
  packet[4] = 0x00

  // PAT section — section is &packet[5], indices below are relative to that.
  let base = 5
  packet[base + 0] = 0x00 // table_id = PAT
  // section_length will be filled after
  packet[base + 3] = 0x00
  packet[base + 4] = 0x01 // transport_stream_id = 1
  packet[base + 5] = 0xC1 // version=0, current_next=1
  packet[base + 6] = 0x00 // section_number
  packet[base + 7] = 0x00 // last_section_number
  // Program 1 -> PMT PID
  packet[base + 8] = 0x00
  packet[base + 9] = 0x01 // program_number = 1
  packet[base + 10] = 0xE0 | UInt8((PMTPID >> 8) & 0x1F)
  packet[base + 11] = UInt8(PMTPID & 0xFF)
  // section_length = 13 (5 bytes after length field + 4 program + 4 CRC)
  let sectionLength: UInt16 = 9 + 4 // 9 bytes data + 4 CRC
  packet[base + 1] = 0xB0 | UInt8((sectionLength >> 8) & 0x0F)
  packet[base + 2] = UInt8(sectionLength & 0xFF)

  let crc = FBMPEGTSCRC32(packet, offset: base, length: 12)
  packet[base + 12] = UInt8((crc >> 24) & 0xFF)
  packet[base + 13] = UInt8((crc >> 16) & 0xFF)
  packet[base + 14] = UInt8((crc >> 8) & 0xFF)
  packet[base + 15] = UInt8(crc & 0xFF)

  return Data(packet)
}

public func FBMPEGTSCreatePMTPacket(_ continuityCounter: inout UInt8, _ streamType: UInt8) -> Data {
  var packet = [UInt8](repeating: 0xFF, count: TSPacketSize)

  // TS header
  packet[0] = TSSyncByte
  packet[1] = 0x40 | UInt8((PMTPID >> 8) & 0x1F) // payload_unit_start=1
  packet[2] = UInt8(PMTPID & 0xFF)
  packet[3] = 0x10 | (continuityCounter & 0x0F)
  continuityCounter &+= 1

  // Pointer field
  packet[4] = 0x00

  // PMT section — section is &packet[5].
  let base = 5
  packet[base + 0] = 0x02 // table_id = PMT
  // section_length filled after
  packet[base + 3] = 0x00
  packet[base + 4] = 0x01 // program_number = 1
  packet[base + 5] = 0xC1 // version=0, current_next=1
  packet[base + 6] = 0x00 // section_number
  packet[base + 7] = 0x00 // last_section_number
  // PCR PID = VideoPID
  packet[base + 8] = 0xE0 | UInt8((VideoPID >> 8) & 0x1F)
  packet[base + 9] = UInt8(VideoPID & 0xFF)
  // program_info_length = 0
  packet[base + 10] = 0xF0
  packet[base + 11] = 0x00
  // Stream entry
  packet[base + 12] = streamType
  packet[base + 13] = 0xE0 | UInt8((VideoPID >> 8) & 0x1F)
  packet[base + 14] = UInt8(VideoPID & 0xFF)
  // ES_info_length = 0
  packet[base + 15] = 0xF0
  packet[base + 16] = 0x00

  let sectionLength: UInt16 = 14 + 4 // 14 bytes data (section[3..16]) + 4 CRC
  packet[base + 1] = 0xB0 | UInt8((sectionLength >> 8) & 0x0F)
  packet[base + 2] = UInt8(sectionLength & 0xFF)

  let crc = FBMPEGTSCRC32(packet, offset: base, length: 17)
  packet[base + 17] = UInt8((crc >> 24) & 0xFF)
  packet[base + 18] = UInt8((crc >> 16) & 0xFF)
  packet[base + 19] = UInt8((crc >> 8) & 0xFF)
  packet[base + 20] = UInt8(crc & 0xFF)

  return Data(packet)
}

// Metadata state used by FBMPEGTSPacketizePES. Mutated under `metadataLock` from the
// metadata APIs; read here without locking, matching the original's single-threaded-write
// assumption (`FBMPEGTSEnableMetadataStream` flips it once at stream start).
private nonisolated(unsafe) var metadataStreamEnabled = false

public func FBMPEGTSPacketizePES(
  _ pesData: Data,
  _ isKeyFrame: Bool,
  _ streamType: UInt8,
  _ pts90k: UInt64,
  _ videoContinuityCounter: inout UInt8,
  _ patContinuityCounter: inout UInt8,
  _ pmtContinuityCounter: inout UInt8
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
    output.append(FBMPEGTSCreatePMTPacketWithMetadata(&pmtContinuityCounter, streamType, metadataStreamEnabled))
  }

  let pesBytes = [UInt8](pesData)
  let pesLength = pesBytes.count
  var pesOffset = 0
  var first = true

  while pesOffset < pesLength {
    var packet = [UInt8](repeating: 0xFF, count: TSPacketSize)

    // TS header (4 bytes)
    packet[0] = TSSyncByte
    packet[1] = (first ? 0x40 : 0x00) | UInt8((VideoPID >> 8) & 0x1F)
    packet[2] = UInt8(VideoPID & 0xFF)

    var headerSize = 4
    let remaining = pesLength - pesOffset

    if first {
      // First packet of each access unit: include adaptation field with PCR
      packet[3] = 0x30 | (videoContinuityCounter & 0x0F) // adaptation + payload
      packet[4] = 0x07 // adaptation_field_length = 7
      packet[5] = 0x10 // flags: PCR present
      // PCR encoding: 33-bit base (90kHz) + 6 reserved bits (all 1) + 9-bit extension (0)
      let pcrBase = pts90k
      packet[6] = UInt8(truncatingIfNeeded: pcrBase >> 25)
      packet[7] = UInt8(truncatingIfNeeded: pcrBase >> 17)
      packet[8] = UInt8(truncatingIfNeeded: pcrBase >> 9)
      packet[9] = UInt8(truncatingIfNeeded: pcrBase >> 1)
      packet[10] = UInt8(truncatingIfNeeded: ((pcrBase & 1) << 7) | 0x7E) // base LSB + 6 reserved bits
      packet[11] = 0x00 // extension = 0
      headerSize = 12

      let payloadCapacity = TSPacketSize - headerSize // 176
      if remaining < payloadCapacity {
        // Extend adaptation field with stuffing bytes
        let stuffingNeeded = payloadCapacity - remaining
        packet[4] = UInt8(0x07 + stuffingNeeded) // extend adaptation_field_length
        for k in 0..<stuffingNeeded {
          packet[12 + k] = 0xFF
        }
        headerSize = 12 + stuffingNeeded
      }
    } else {
      let payloadCapacity = TSPacketSize - headerSize // 184
      if remaining < payloadCapacity {
        // Need adaptation field for stuffing
        let stuffingBytes = payloadCapacity - remaining
        if stuffingBytes == 1 {
          // adaptation_field_length = 0, just the length byte
          packet[3] = 0x30 | (videoContinuityCounter & 0x0F)
          packet[4] = 0x00 // adaptation_field_length = 0
          headerSize = 5
        } else {
          packet[3] = 0x30 | (videoContinuityCounter & 0x0F)
          packet[4] = UInt8(stuffingBytes - 1) // adaptation_field_length
          if stuffingBytes > 1 {
            packet[5] = 0x00 // flags
            for k in 0..<(stuffingBytes - 2) {
              packet[6 + k] = 0xFF
            }
          }
          headerSize = 4 + stuffingBytes
        }
      } else {
        packet[3] = 0x10 | (videoContinuityCounter & 0x0F)
      }
    }

    videoContinuityCounter &+= 1
    var payloadSize = TSPacketSize - headerSize
    if payloadSize > remaining {
      payloadSize = remaining
    }
    for k in 0..<payloadSize {
      packet[headerSize + k] = pesBytes[pesOffset + k]
    }
    pesOffset += payloadSize
    first = false

    output.append(contentsOf: packet)
  }

  return output
}

public func FBMPEGTSCreatePMTPacketWithMetadata(_ continuityCounter: inout UInt8, _ streamType: UInt8, _ includeMetadataStream: Bool) -> Data {
  if !includeMetadataStream {
    return FBMPEGTSCreatePMTPacket(&continuityCounter, streamType)
  }

  var packet = [UInt8](repeating: 0xFF, count: TSPacketSize)

  // TS header
  packet[0] = TSSyncByte
  packet[1] = 0x40 | UInt8((PMTPID >> 8) & 0x1F)
  packet[2] = UInt8(PMTPID & 0xFF)
  packet[3] = 0x10 | (continuityCounter & 0x0F)
  continuityCounter &+= 1

  // Pointer field
  packet[4] = 0x00

  // PMT section — section is &packet[5].
  let base = 5
  packet[base + 0] = 0x02 // table_id = PMT
  packet[base + 3] = 0x00
  packet[base + 4] = 0x01 // program_number = 1
  packet[base + 5] = 0xC1 // version=0, current_next=1
  packet[base + 6] = 0x00 // section_number
  packet[base + 7] = 0x00 // last_section_number
  // PCR PID = VideoPID
  packet[base + 8] = 0xE0 | UInt8((VideoPID >> 8) & 0x1F)
  packet[base + 9] = UInt8(VideoPID & 0xFF)
  // program_info_length = 0
  packet[base + 10] = 0xF0
  packet[base + 11] = 0x00
  // Video stream entry
  packet[base + 12] = streamType
  packet[base + 13] = 0xE0 | UInt8((VideoPID >> 8) & 0x1F)
  packet[base + 14] = UInt8(VideoPID & 0xFF)
  packet[base + 15] = 0xF0
  packet[base + 16] = 0x00 // ES_info_length = 0
  // Metadata stream entry
  packet[base + 17] = TimedMetadataStreamType
  packet[base + 18] = 0xE0 | UInt8((FBMPEGTSMetadataPID >> 8) & 0x1F)
  packet[base + 19] = UInt8(FBMPEGTSMetadataPID & 0xFF)
  packet[base + 20] = 0xF0
  packet[base + 21] = 0x00 // ES_info_length = 0

  // section_length = 9 (header after length) + 5 (video entry) + 5 (metadata entry) + 4 (CRC) = 23
  // But PMT section data before CRC is: bytes [3..21] = 19 bytes. section_length covers from byte [3] to end including CRC.
  // section_length = (21 - 3 + 1) + 4 = 23
  let sectionLength: UInt16 = 18 + 4 // 18 bytes data after section_length field + 4 CRC
  packet[base + 1] = 0xB0 | UInt8((sectionLength >> 8) & 0x0F)
  packet[base + 2] = UInt8(sectionLength & 0xFF)

  let crc = FBMPEGTSCRC32(packet, offset: base, length: 22)
  packet[base + 22] = UInt8((crc >> 24) & 0xFF)
  packet[base + 23] = UInt8((crc >> 16) & 0xFF)
  packet[base + 24] = UInt8((crc >> 8) & 0xFF)
  packet[base + 25] = UInt8(crc & 0xFF)

  return Data(packet)
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
  let pesLength = pesBytes.count
  let numPackets = (pesLength + 183) / 184
  var output = Data(capacity: numPackets * TSPacketSize)

  var pesOffset = 0
  var first = true

  while pesOffset < pesLength {
    var packet = [UInt8](repeating: 0xFF, count: TSPacketSize)
    packet[0] = TSSyncByte
    packet[1] = (first ? 0x40 : 0x00) | UInt8((FBMPEGTSMetadataPID >> 8) & 0x1F)
    packet[2] = UInt8(FBMPEGTSMetadataPID & 0xFF)

    var headerSize = 4
    let remaining = pesLength - pesOffset
    let payloadCapacity = TSPacketSize - headerSize // 184

    if remaining < payloadCapacity {
      let stuffingBytes = payloadCapacity - remaining
      if stuffingBytes == 1 {
        packet[3] = 0x30 | (metadataContinuityCounter & 0x0F)
        packet[4] = 0x00
        headerSize = 5
      } else {
        packet[3] = 0x30 | (metadataContinuityCounter & 0x0F)
        packet[4] = UInt8(stuffingBytes - 1)
        if stuffingBytes > 1 {
          packet[5] = 0x00
          if stuffingBytes > 2 {
            for k in 0..<(stuffingBytes - 2) {
              packet[6 + k] = 0xFF
            }
          }
        }
        headerSize = 4 + stuffingBytes
      }
    } else {
      packet[3] = 0x10 | (metadataContinuityCounter & 0x0F)
    }

    metadataContinuityCounter &+= 1
    var payloadSize = TSPacketSize - headerSize
    if payloadSize > remaining {
      payloadSize = remaining
    }
    for k in 0..<payloadSize {
      packet[headerSize + k] = pesBytes[pesOffset + k]
    }
    pesOffset += payloadSize
    first = false

    output.append(contentsOf: packet)
  }

  return output
}

// MARK: - MPEG-TS Metadata State

// Guards the process-global metadata state, matching the original's `os_unfair_lock metadataLock`.
// `NSLock` preserves the same lock/unlock discipline; the lock is only ever held briefly to read or
// flip a few scalars, so the choice of primitive does not affect byte output.
private let metadataLock = NSLock()
private nonisolated(unsafe) var metadataContinuityCounter: UInt8 = 0
private nonisolated(unsafe) var lastPts90k: UInt64 = 0

public func FBMPEGTSEnableMetadataStream() {
  metadataLock.lock()
  metadataStreamEnabled = true
  metadataLock.unlock()
}

public func FBMPEGTSWriteTimedMetadata(_ text: String, _ consumer: any FBDataConsumer) {
  metadataLock.lock()
  if !metadataStreamEnabled {
    metadataLock.unlock()
    return
  }
  let pts = lastPts90k
  let packets = FBMPEGTSCreateTimedMetadataPackets(text, pts, &metadataContinuityCounter)
  metadataLock.unlock()

  consumer.consumeData(packets)
}

// Continuity counters persist across calls via file-private globals (function-`static` in the original).
private nonisolated(unsafe) var mpegtsVideoContinuityCounter: UInt8 = 0
private nonisolated(unsafe) var mpegtsPATContinuityCounter: UInt8 = 0
private nonisolated(unsafe) var mpegtsPMTContinuityCounter: UInt8 = 0

private func WriteCodecFrameToMPEGTSStream(_ sampleBuffer: CMSampleBuffer, _ paramSetGetter: FBVideoParameterSetGetter, _ codecName: String, _ mpegtsStreamType: UInt8, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  if !CMSampleBufferDataIsReady(sampleBuffer) {
    throw FBVideoStreamWriterError.sampleBufferNotReady
  }

  var isKeyFrame = false
  if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true), CFArrayGetCount(attachments) != 0 {
    let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
    isKeyFrame = !CFDictionaryContainsKey(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
  }

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
    var status = paramSetGetter(format, 0, nil, nil, &parameterSetCount, nil)
    if status != noErr {
      throw FBVideoStreamWriterError.failedToGetParameterSetCount(codecName: codecName, status: status)
    }
    for i in 0..<parameterSetCount {
      var paramSize = 0
      status = paramSetGetter(format, i, nil, &paramSize, nil, nil)
      if status != noErr {
        throw FBVideoStreamWriterError.failedToGetParameterSet(codecName: codecName, index: i, status: status)
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

  // Update the shared last PTS for timed metadata injection
  metadataLock.lock()
  lastPts90k = pts90k
  metadataLock.unlock()

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
      _ = paramSetGetter(format, i, &parameterSet, &paramSize, nil, nil)
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
    mpegtsStreamType,
    pts90k,
    &mpegtsVideoContinuityCounter,
    &mpegtsPATContinuityCounter,
    &mpegtsPMTContinuityCounter
  )
  consumer.consumeData(tsData)
}

public func WriteHEVCFrameToMPEGTSStream(_ sampleBuffer: CMSampleBuffer, _ context: Any?, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  try WriteCodecFrameToMPEGTSStream(sampleBuffer, CMVideoFormatDescriptionGetHEVCParameterSetAtIndex, "HEVC", HEVCStreamType, consumer, logger)
}

public func WriteH264FrameToMPEGTSStream(_ sampleBuffer: CMSampleBuffer, _ context: Any?, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  try WriteCodecFrameToMPEGTSStream(sampleBuffer, CMVideoFormatDescriptionGetH264ParameterSetAtIndex, "H264", H264StreamType, consumer, logger)
}

public func WriteJPEGDataToMJPEGStream(_ jpegDataBuffer: CMBlockBuffer, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  try WriteBlockBufferToConsumer(jpegDataBuffer, consumer)
}

public func WriteJPEGDataToMinicapStream(_ jpegDataBuffer: CMBlockBuffer, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  // Write the header length first
  let dataLength = CMBlockBufferGetDataLength(jpegDataBuffer)
  var imageLength = UInt32(dataLength).littleEndian
  let lengthData = Data(bytes: &imageLength, count: MemoryLayout<UInt32>.size)
  consumer.consumeData(lengthData)

  try WriteJPEGDataToMJPEGStream(jpegDataBuffer, consumer, logger)
}

// MinicapHeader is built byte-by-byte (24 bytes, all little-endian) rather than relying
// on Swift struct layout, matching the `#pragma pack(push, 1)` C struct.
// https://github.com/openstf/minicap#usage
public func WriteMinicapHeaderToStream(_ width: UInt32, _ height: UInt32, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) {
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

// MARK: - Fragmented MP4 (fMP4) Writer

// ISO BMFF box helpers — all values are big-endian per spec.

private func FBFMP4Write8(_ data: inout [UInt8], _ value: UInt8) {
  data.append(value)
}

private func FBFMP4Write16(_ data: inout [UInt8], _ value: UInt16) {
  let be = value.bigEndian
  withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
}

private func FBFMP4Write32(_ data: inout [UInt8], _ value: UInt32) {
  let be = value.bigEndian
  withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
}

private func FBFMP4Write64(_ data: inout [UInt8], _ value: UInt64) {
  let be = value.bigEndian
  withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
}

private func FBFMP4BeginBox(_ data: inout [UInt8], _ type: String) -> Int {
  let offset = data.count
  FBFMP4Write32(&data, 0)
  data.append(contentsOf: Array(type.utf8))
  return offset
}

private func FBFMP4EndBox(_ data: inout [UInt8], _ sizeOffset: Int) {
  let size = UInt32(data.count - sizeOffset)
  let be = size.bigEndian
  withUnsafeBytes(of: be) { bytes in
    for k in 0..<4 {
      data[sizeOffset + k] = bytes[k]
    }
  }
}

private func FBFMP4WriteFullBoxHeader(_ data: inout [UInt8], _ version: UInt8, _ flags: UInt32) {
  let vf = (UInt32(version) << 24) | (flags & 0x00FFFFFF)
  FBFMP4Write32(&data, vf)
}

private func FBFMP4WriteZeros(_ data: inout [UInt8], _ count: Int) {
  assert(count <= 64, "Zero count greater than 64")
  data.append(contentsOf: [UInt8](repeating: 0, count: count))
}

private func FBFMP4WriteBytes(_ data: inout [UInt8], _ string: String) {
  data.append(contentsOf: Array(string.utf8))
}

// Extract codec configuration atom (avcC or hvcC) from CMFormatDescription.
private func FBFMP4GetCodecConfigAtom(_ formatDescription: CMFormatDescription, _ isHEVC: Bool) -> [UInt8]? {
  if let atoms = CMFormatDescriptionGetExtension(formatDescription, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any] {
    let key = isHEVC ? "hvcC" : "avcC"
    if let configData = atoms[key] as? Data {
      return [UInt8](configData)
    }
  }
  // Fallback: build avcC/hvcC manually from parameter sets.
  var config = [UInt8]()
  if !isHEVC {
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

    FBFMP4Write8(&config, 1)
    FBFMP4Write8(&config, sps[1])
    FBFMP4Write8(&config, sps[2])
    FBFMP4Write8(&config, sps[3])
    FBFMP4Write8(&config, 0xFF)
    FBFMP4Write8(&config, 0xE1)
    FBFMP4Write16(&config, UInt16(spsSize))
    config.append(contentsOf: UnsafeBufferPointer(start: sps, count: spsSize))
    FBFMP4Write8(&config, pps != nil ? 1 : 0)
    if let pps {
      FBFMP4Write16(&config, UInt16(ppsSize))
      config.append(contentsOf: UnsafeBufferPointer(start: pps, count: ppsSize))
    }
  } else {
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

    FBFMP4Write8(&config, 1)
    FBFMP4Write8(&config, 0)
    FBFMP4Write32(&config, 0)
    FBFMP4Write16(&config, 0)
    FBFMP4Write32(&config, 0)
    FBFMP4Write8(&config, 0)
    FBFMP4Write16(&config, 0xF000)
    FBFMP4Write8(&config, 0xFC)
    FBFMP4Write8(&config, 0xFC)
    FBFMP4Write8(&config, 0xF8)
    FBFMP4Write8(&config, 0xF8)
    FBFMP4Write16(&config, 0)
    FBFMP4Write8(&config, 0x0F)

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

    FBFMP4Write8(&config, UInt8(groupedOrder.count))
    for nalType in groupedOrder {
      let sets = grouped[nalType] ?? []
      FBFMP4Write8(&config, nalType & 0x3F)
      FBFMP4Write16(&config, UInt16(sets.count))
      for set in sets {
        FBFMP4Write16(&config, UInt16(set.count))
        config.append(contentsOf: set)
      }
    }
  }
  return config
}

private func FBFMP4CreateFtypBox(_ isHEVC: Bool) -> [UInt8] {
  var data = [UInt8]()
  data.reserveCapacity(24)
  let off = FBFMP4BeginBox(&data, "ftyp")
  FBFMP4WriteBytes(&data, "isom")
  FBFMP4Write32(&data, 0x200)
  FBFMP4WriteBytes(&data, "isom")
  FBFMP4WriteBytes(&data, "iso6")
  if isHEVC {
    FBFMP4WriteBytes(&data, "hvc1")
  } else {
    FBFMP4WriteBytes(&data, "mp41")
  }
  FBFMP4EndBox(&data, off)
  return data
}

private func FBFMP4CreateMoovBox(_ formatDescription: CMFormatDescription, _ isHEVC: Bool, _ width: UInt32, _ height: UInt32, _ timescale: UInt32) -> [UInt8] {
  var data = [UInt8]()
  data.reserveCapacity(512)

  let codecConfig = FBFMP4GetCodecConfigAtom(formatDescription, isHEVC)
  let sampleEntryType = isHEVC ? "hvc1" : "avc1"
  let codecConfigType = isHEVC ? "hvcC" : "avcC"

  let moovOff = FBFMP4BeginBox(&data, "moov")

  // mvhd
  do {
    let off = FBFMP4BeginBox(&data, "mvhd")
    FBFMP4WriteFullBoxHeader(&data, 0, 0)
    FBFMP4Write32(&data, 0)
    FBFMP4Write32(&data, 0)
    FBFMP4Write32(&data, timescale)
    FBFMP4Write32(&data, 0)
    FBFMP4Write32(&data, 0x00010000)
    FBFMP4Write16(&data, 0x0100)
    FBFMP4WriteZeros(&data, 10)
    let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
    for i in 0..<9 {
      FBFMP4Write32(&data, matrix[i])
    }
    FBFMP4WriteZeros(&data, 24)
    FBFMP4Write32(&data, 2)
    FBFMP4EndBox(&data, off)
  }

  // trak
  do {
    let trakOff = FBFMP4BeginBox(&data, "trak")

    // tkhd
    do {
      let off = FBFMP4BeginBox(&data, "tkhd")
      FBFMP4WriteFullBoxHeader(&data, 0, 0x03)
      FBFMP4Write32(&data, 0)
      FBFMP4Write32(&data, 0)
      FBFMP4Write32(&data, 1)
      FBFMP4Write32(&data, 0)
      FBFMP4Write32(&data, 0)
      FBFMP4WriteZeros(&data, 8)
      FBFMP4Write16(&data, 0)
      FBFMP4Write16(&data, 0)
      FBFMP4Write16(&data, 0)
      FBFMP4Write16(&data, 0)
      let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
      for i in 0..<9 {
        FBFMP4Write32(&data, matrix[i])
      }
      FBFMP4Write32(&data, width << 16)
      FBFMP4Write32(&data, height << 16)
      FBFMP4EndBox(&data, off)
    }

    // mdia
    do {
      let mdiaOff = FBFMP4BeginBox(&data, "mdia")

      // mdhd
      do {
        let off = FBFMP4BeginBox(&data, "mdhd")
        FBFMP4WriteFullBoxHeader(&data, 0, 0)
        FBFMP4Write32(&data, 0)
        FBFMP4Write32(&data, 0)
        FBFMP4Write32(&data, timescale)
        FBFMP4Write32(&data, 0)
        FBFMP4Write16(&data, 0x55C4)
        FBFMP4Write16(&data, 0)
        FBFMP4EndBox(&data, off)
      }

      // hdlr
      do {
        let off = FBFMP4BeginBox(&data, "hdlr")
        FBFMP4WriteFullBoxHeader(&data, 0, 0)
        FBFMP4Write32(&data, 0)
        FBFMP4WriteBytes(&data, "vide")
        FBFMP4WriteZeros(&data, 12)
        let name = "VideoHandler"
        FBFMP4WriteBytes(&data, name)
        FBFMP4Write8(&data, 0) // null terminator (strlen(name) + 1)
        FBFMP4EndBox(&data, off)
      }

      // minf
      do {
        let minfOff = FBFMP4BeginBox(&data, "minf")

        // vmhd
        do {
          let off = FBFMP4BeginBox(&data, "vmhd")
          FBFMP4WriteFullBoxHeader(&data, 0, 1)
          FBFMP4Write16(&data, 0)
          FBFMP4WriteZeros(&data, 6)
          FBFMP4EndBox(&data, off)
        }

        // dinf → dref → url
        do {
          let dinfOff = FBFMP4BeginBox(&data, "dinf")
          let drefOff = FBFMP4BeginBox(&data, "dref")
          FBFMP4WriteFullBoxHeader(&data, 0, 0)
          FBFMP4Write32(&data, 1)
          let urlOff = FBFMP4BeginBox(&data, "url ")
          FBFMP4WriteFullBoxHeader(&data, 0, 1)
          FBFMP4EndBox(&data, urlOff)
          FBFMP4EndBox(&data, drefOff)
          FBFMP4EndBox(&data, dinfOff)
        }

        // stbl
        do {
          let stblOff = FBFMP4BeginBox(&data, "stbl")

          // stsd
          do {
            let stsdOff = FBFMP4BeginBox(&data, "stsd")
            FBFMP4WriteFullBoxHeader(&data, 0, 0)
            FBFMP4Write32(&data, 1)

            // Visual sample entry (avc1 or hvc1)
            do {
              let entryOff = FBFMP4BeginBox(&data, sampleEntryType)
              FBFMP4WriteZeros(&data, 6)
              FBFMP4Write16(&data, 1)
              FBFMP4WriteZeros(&data, 16)
              FBFMP4Write16(&data, UInt16(width))
              FBFMP4Write16(&data, UInt16(height))
              FBFMP4Write32(&data, 0x00480000)
              FBFMP4Write32(&data, 0x00480000)
              FBFMP4Write32(&data, 0)
              FBFMP4Write16(&data, 1)
              FBFMP4WriteZeros(&data, 32)
              FBFMP4Write16(&data, 0x0018)
              FBFMP4Write16(&data, 0xFFFF)

              if let codecConfig {
                let ccOff = FBFMP4BeginBox(&data, codecConfigType)
                data.append(contentsOf: codecConfig)
                FBFMP4EndBox(&data, ccOff)
              }

              FBFMP4EndBox(&data, entryOff)
            }

            FBFMP4EndBox(&data, stsdOff)
          }

          // Empty required boxes
          do {
            var off = FBFMP4BeginBox(&data, "stts")
            FBFMP4WriteFullBoxHeader(&data, 0, 0)
            FBFMP4Write32(&data, 0)
            FBFMP4EndBox(&data, off)

            off = FBFMP4BeginBox(&data, "stsc")
            FBFMP4WriteFullBoxHeader(&data, 0, 0)
            FBFMP4Write32(&data, 0)
            FBFMP4EndBox(&data, off)

            off = FBFMP4BeginBox(&data, "stsz")
            FBFMP4WriteFullBoxHeader(&data, 0, 0)
            FBFMP4Write32(&data, 0)
            FBFMP4Write32(&data, 0)
            FBFMP4EndBox(&data, off)

            off = FBFMP4BeginBox(&data, "stco")
            FBFMP4WriteFullBoxHeader(&data, 0, 0)
            FBFMP4Write32(&data, 0)
            FBFMP4EndBox(&data, off)
          }

          FBFMP4EndBox(&data, stblOff)
        }

        FBFMP4EndBox(&data, minfOff)
      }

      FBFMP4EndBox(&data, mdiaOff)
    }

    FBFMP4EndBox(&data, trakOff)
  }

  // mvex
  do {
    let mvexOff = FBFMP4BeginBox(&data, "mvex")
    let trexOff = FBFMP4BeginBox(&data, "trex")
    FBFMP4WriteFullBoxHeader(&data, 0, 0)
    FBFMP4Write32(&data, 1)
    FBFMP4Write32(&data, 1)
    FBFMP4Write32(&data, 0)
    FBFMP4Write32(&data, 0)
    FBFMP4Write32(&data, 0)
    FBFMP4EndBox(&data, trexOff)
    FBFMP4EndBox(&data, mvexOff)
  }

  FBFMP4EndBox(&data, moovOff)
  return data
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

  var data = [UInt8]()
  data.reserveCapacity(moofSize + mdatHeaderSize)

  let moofOff = FBFMP4BeginBox(&data, "moof")

  // mfhd
  do {
    let off = FBFMP4BeginBox(&data, "mfhd")
    FBFMP4WriteFullBoxHeader(&data, 0, 0)
    FBFMP4Write32(&data, sequenceNumber)
    FBFMP4EndBox(&data, off)
  }

  // traf
  do {
    let trafOff = FBFMP4BeginBox(&data, "traf")

    // tfhd
    do {
      let off = FBFMP4BeginBox(&data, "tfhd")
      FBFMP4WriteFullBoxHeader(&data, 0, 0x020000)
      FBFMP4Write32(&data, 1)
      FBFMP4EndBox(&data, off)
    }

    // tfdt
    do {
      let off = FBFMP4BeginBox(&data, "tfdt")
      FBFMP4WriteFullBoxHeader(&data, 1, 0)
      FBFMP4Write64(&data, baseDecodeTime)
      FBFMP4EndBox(&data, off)
    }

    // trun — single sample
    do {
      _ = FBFMP4BeginBox(&data, "trun")
      FBFMP4WriteFullBoxHeader(&data, 0, trunFlags)
      FBFMP4Write32(&data, 1) // sample_count = 1
      FBFMP4Write32(&data, 0) // placeholder for data_offset (patched below)
      FBFMP4Write32(&data, duration)
      FBFMP4Write32(&data, sampleSize)
      FBFMP4Write32(&data, isKeyFrame ? 0x02000000 : 0x01010000)
    }

    FBFMP4EndBox(&data, trafOff)
  }

  FBFMP4EndBox(&data, moofOff)

  // Patch data_offset: distance from moof start to first sample byte in mdat.
  let actualMoofSize = UInt32(data.count - moofOff)
  let dataOffset = actualMoofSize + UInt32(mdatHeaderSize)
  // dataOffsetPos = moofOff + moof_header(8) + mfhd(16) + traf_header(8) + tfhd(16) + tfdt(20) + trun_header(12) + sample_count(4)
  let patchPos = moofOff + 8 + 16 + 8 + 16 + 20 + 12 + 4
  let dataOffsetBE = dataOffset.bigEndian
  withUnsafeBytes(of: dataOffsetBE) { bytes in
    for k in 0..<4 {
      data[patchPos + k] = bytes[k]
    }
  }

  // mdat header only — caller appends sample data.
  FBFMP4Write32(&data, UInt32(mdatHeaderSize) + sampleSize)
  FBFMP4WriteBytes(&data, "mdat")

  return data
}

/// Muxer context for fragmented MP4 (fMP4) output.
/// Minimal state holder — all frame writing logic lives in the writer functions.
/// Created per video stream — no static/global state.
public final class FBFMP4MuxerContext {
  public let isHEVC: Bool
  public var initWritten: Bool
  public var sequenceNumber: UInt32
  public var baseDecodeTime: UInt64
  public var lastPts90k: UInt64

  public init(hevc isHEVC: Bool) {
    self.isHEVC = isHEVC
    self.initWritten = false
    self.sequenceNumber = 0
    self.baseDecodeTime = 0
    self.lastPts90k = 0
  }
}

// Per-frame fMP4 writer: each frame is immediately emitted as a single-sample moof+mdat fragment.
private func WriteCodecFrameToFMP4Stream(_ sampleBuffer: CMSampleBuffer, _ context: Any?, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  guard let ctx = context as? FBFMP4MuxerContext else {
    throw FBVideoStreamWriterError.fmp4WriterCalledWithoutContext
  }

  if !CMSampleBufferDataIsReady(sampleBuffer) {
    throw FBVideoStreamWriterError.sampleBufferNotReady
  }

  // Detect keyframe.
  var isKeyFrame = false
  if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true), CFArrayGetCount(attachments) != 0 {
    let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
    isKeyFrame = !CFDictionaryContainsKey(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
  }

  // Extract PTS.
  let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
  let pts90k = UInt64(CMTimeGetSeconds(pts) * 90000.0)
  let prevPts90k = ctx.lastPts90k
  ctx.lastPts90k = pts90k

  // On first keyframe: emit init segment (ftyp + moov).
  if !ctx.initWritten {
    if !isKeyFrame {
      return // Drop frames before first keyframe.
    }

    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      throw FBVideoStreamWriterError.failedToGetFormatDescription
    }
    let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)

    let ftyp = FBFMP4CreateFtypBox(ctx.isHEVC)
    let moov = FBFMP4CreateMoovBox(formatDesc, ctx.isHEVC, UInt32(dims.width), UInt32(dims.height), 90000)

    consumer.consumeData(Data(ftyp))
    consumer.consumeData(Data(moov))

    ctx.initWritten = true
    ctx.baseDecodeTime = pts90k
    logger.log("fMP4 init segment written (\(dims.width)x\(dims.height), \(ctx.isHEVC ? "HEVC" : "H264"))")
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
  ctx.sequenceNumber += 1
  let header = FBFMP4CreateFragmentHeader(ctx.sequenceNumber, ctx.baseDecodeTime, duration90k, UInt32(dataLength), isKeyFrame)
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

  ctx.baseDecodeTime += UInt64(duration90k)
}

public func WriteH264FrameToFMP4Stream(_ sampleBuffer: CMSampleBuffer, _ context: Any?, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  try WriteCodecFrameToFMP4Stream(sampleBuffer, context, consumer, logger)
}

public func WriteHEVCFrameToFMP4Stream(_ sampleBuffer: CMSampleBuffer, _ context: Any?, _ consumer: any FBDataConsumer, _ logger: any FBControlCoreLogger) throws {
  try WriteCodecFrameToFMP4Stream(sampleBuffer, context, consumer, logger)
}

public func FBFMP4WriteEmsgBox(_ context: FBFMP4MuxerContext, _ text: String, _ consumer: any FBDataConsumer) {
  let textData = [UInt8](text.utf8)

  var data = [UInt8]()
  data.reserveCapacity(64 + textData.count)

  let off = FBFMP4BeginBox(&data, "emsg")
  FBFMP4WriteFullBoxHeader(&data, 1, 0)
  FBFMP4Write32(&data, 90000)
  FBFMP4Write64(&data, context.lastPts90k)
  FBFMP4Write32(&data, 0)
  FBFMP4Write32(&data, 0)

  let scheme = "urn:sime2e:chapter"
  FBFMP4WriteBytes(&data, scheme)
  FBFMP4Write8(&data, 0) // null terminator (strlen(scheme) + 1)
  FBFMP4Write8(&data, 0) // empty value string
  data.append(contentsOf: textData)

  FBFMP4EndBox(&data, off)

  consumer.consumeData(Data(data))
}
