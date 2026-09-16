/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation

private let TSPacketSize: Int = 188
private let TSSyncByte: UInt8 = 0x47
private let PATPID: UInt16 = 0x0000
private let PMTPID: UInt16 = 0x0100
private let VideoPID: UInt16 = 0x0101
let FBMPEGTSMetadataPID: UInt16 = 0x0102
private let HEVCStreamType: UInt8 = 0x24
private let H264StreamType: UInt8 = 0x1B
private let TimedMetadataStreamType: UInt8 = 0x15 // PES private data (ID3)

extension VideoStreamCodec {
  var mpegtsStreamType: UInt8 {
    switch self {
    case .h264:
      return H264StreamType
    case .hevc:
      return HEVCStreamType
    }
  }
}

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

func FBMPEGTS_CRC32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
  var crc: UInt32 = 0xFFFFFFFF
  for byte in bytes {
    crc = (crc << 8) ^ FBMPEGTSCRC32Table[Int(((crc >> 24) ^ UInt32(byte)) & 0xFF)]
  }
  return crc
}

private struct MPEGTSSection {
  let startOffset: Int
  let lengthOffset: Int
}

private struct MPEGTSPacketWriter {
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

  mutating func beginSection(tableID: UInt8) -> MPEGTSSection {
    let startOffset = cursor
    write8(tableID)
    let lengthOffset = cursor
    write16(0)
    return MPEGTSSection(startOffset: startOffset, lengthOffset: lengthOffset)
  }

  mutating func finishSection(_ section: MPEGTSSection) {
    let sectionLength = UInt16(cursor - (section.lengthOffset + 2) + 4)
    packet[section.lengthOffset] = 0xB0 | UInt8((sectionLength >> 8) & 0x0F)
    packet[section.lengthOffset + 1] = UInt8(sectionLength & 0xFF)
    write32(FBMPEGTS_CRC32(packet[section.startOffset..<cursor]))
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

func FBMPEGTSCreatePATPacket(_ continuityCounter: inout UInt8) -> Data {
  var writer = MPEGTSPacketWriter(pid: PATPID, payloadUnitStart: true, continuityCounter: &continuityCounter)
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

func FBMPEGTSCreatePMTPacket(_ continuityCounter: inout UInt8, _ streamType: UInt8) -> Data {
  var writer = MPEGTSPacketWriter(pid: PMTPID, payloadUnitStart: true, continuityCounter: &continuityCounter)
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

func FBMPEGTSPacketizePES(
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

func FBMPEGTSCreatePMTPacketWithMetadata(_ continuityCounter: inout UInt8, _ streamType: UInt8, _ includeMetadataStream: Bool) -> Data {
  if !includeMetadataStream {
    return FBMPEGTSCreatePMTPacket(&continuityCounter, streamType)
  }

  var writer = MPEGTSPacketWriter(pid: PMTPID, payloadUnitStart: true, continuityCounter: &continuityCounter)
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

func FBMPEGTSCreateTimedMetadataPackets(_ text: String, _ pts90k: UInt64, _ metadataContinuityCounter: inout UInt8) -> Data {
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
  id3Tag.append(contentsOf: [0x03, 0x00])
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

/// The program map always declares the timed-metadata stream, so a marker written at any point —
/// including before the first keyframe — travels on a PID every demuxer already knows about. An
/// elementary stream that never carries a packet costs nothing.
public final class MPEGTSFrameWriter: EncodedFrameWriter, VideoStreamTimedMetadataWriter {
  private let codec: VideoStreamCodec
  private let metadataLock = NSLock()
  private var metadataContinuityCounter: UInt8 = 0
  private var lastPts90k: UInt64 = 0
  private var videoContinuityCounter: UInt8 = 0
  private var patContinuityCounter: UInt8 = 0
  private var pmtContinuityCounter: UInt8 = 0

  public init(codec: VideoStreamCodec) {
    self.codec = codec
  }

  private func timedMetadataPackets(for text: String) -> Data {
    metadataLock.lock()
    defer { metadataLock.unlock() }
    return FBMPEGTSCreateTimedMetadataPackets(text, lastPts90k, &metadataContinuityCounter)
  }

  private func recordVideoPTS(_ pts90k: UInt64) {
    metadataLock.lock()
    defer { metadataLock.unlock() }
    lastPts90k = pts90k
  }

  public func write(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) throws {
    if !CMSampleBufferDataIsReady(sampleBuffer) {
      throw VideoStreamWriterError.sampleBufferNotReady
    }

    let isKeyFrame = FBVideoSampleBufferIsKeyFrame(sampleBuffer)

    // AVCC length prefixes and Annex-B start codes are both 4 bytes, so sizes are unchanged by the conversion.
    try ConvertAVCCToAnnexBInPlace(sampleBuffer)

    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw VideoStreamWriterError.failedToGetDataBuffer
    }
    let dataLength = CMBlockBufferGetDataLength(dataBuffer)

    // Compute parameter set sizes upfront (if keyframe) so we can allocate a single buffer.
    var parameterSetSize = 0
    var format: CMFormatDescription?
    var parameterSetCount = 0
    if isKeyFrame {
      format = CMSampleBufferGetFormatDescription(sampleBuffer)
      guard let format else {
        throw VideoStreamWriterError.failedToGetFormatDescription
      }
      var status = codec.parameterSetGetter(format, 0, nil, nil, &parameterSetCount, nil)
      if status != noErr {
        throw VideoStreamWriterError.failedToGetParameterSetCount(codecName: codec.displayName, status: status)
      }
      for i in 0..<parameterSetCount {
        var paramSize = 0
        status = codec.parameterSetGetter(format, i, nil, &paramSize, nil, nil)
        if status != noErr {
          throw VideoStreamWriterError.failedToGetParameterSet(codecName: codec.displayName, index: i, status: status)
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

    recordVideoPTS(pts90k)

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

    // CMBlockBufferCopyDataBytes handles non-contiguous block buffers.
    let nalDestOffset = pesPacket.count
    pesPacket.append(contentsOf: [UInt8](repeating: 0, count: dataLength))
    let copyStatus = pesPacket.withUnsafeMutableBufferPointer { ptr -> OSStatus in
      guard let nalDest = ptr.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
      return CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: dataLength, destination: nalDest + nalDestOffset)
    }
    if copyStatus != noErr {
      throw VideoStreamWriterError.failedToCopyBlockBufferData(status: copyStatus)
    }

    let tsData = FBMPEGTSPacketizePES(
      Data(pesPacket),
      isKeyFrame,
      codec.mpegtsStreamType,
      pts90k,
      &videoContinuityCounter,
      &patContinuityCounter,
      &pmtContinuityCounter,
      true
    )
    consumer.consumeData(tsData)
  }

  public func writeTimedMetadata(_ text: String, to consumer: any DataConsumer) {
    consumer.consumeData(timedMetadataPackets(for: text))
  }
}
