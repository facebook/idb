/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation
import os

/// MPEG-2 transport stream (ISO 13818-1) packetisation for a single-program stream: one video
/// elementary stream and one ID3 timed-metadata stream. Everything here is a pure function of its
/// arguments; the per-stream state (continuity counters, last PTS) lives in `MPEGTSFrameWriter`.
enum MPEGTS {
  static let packetSize = 188
  static let syncByte: UInt8 = 0x47
  /// Program and elementary stream identifiers.
  enum PID {
    static let pat: UInt16 = 0x0000
    static let pmt: UInt16 = 0x0100
    static let video: UInt16 = 0x0101
    static let timedMetadata: UInt16 = 0x0102
  }
  /// PMT `stream_type` values.
  enum StreamType {
    static let h264: UInt8 = 0x1B
    static let hevc: UInt8 = 0x24
    /// PES private data, carrying ID3.
    static let timedMetadata: UInt8 = 0x15
  }
  /// PES `stream_id` values.
  private enum StreamID {
    static let video: UInt8 = 0xE0
    static let privateStream1: UInt8 = 0xBD
  }
  private static let payloadCapacity = packetSize - 4
  /// A PCR adaptation field consumes eight bytes of the first packet's payload.
  private static let payloadCapacityWithPCR = packetSize - 12

  // MARK: - CRC

  private static let crc32Table: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
      var crc = UInt32(i) << 24
      for _ in 0..<8 {
        if crc & 0x8000_0000 != 0 {
          crc = (crc << 1) ^ 0x04C1_1DB7
        } else {
          crc <<= 1
        }
      }
      table[i] = crc
    }
    return table
  }()

  /// The MPEG-2 section CRC (CRC-32/MPEG-2: polynomial 0x04C11DB7, initial 0xFFFFFFFF, no reflection).
  static func crc32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
      crc = (crc << 8) ^ crc32Table[Int(((crc >> 24) ^ UInt32(byte)) & 0xFF)]
    }
    return crc
  }

  // MARK: - Program tables

  /// Builds one 188-byte packet carrying a PSI section, stuffed with 0xFF.
  private struct SectionPacketWriter {
    private var packet = [UInt8](repeating: 0xFF, count: MPEGTS.packetSize)
    private var cursor = 0
    private var sectionStart = 0
    private var sectionLengthOffset = 0

    init(pid: UInt16, continuityCounter: inout UInt8) {
      packet[0] = MPEGTS.syncByte
      packet[1] = 0x40 | UInt8((pid >> 8) & 0x1F) // payload_unit_start_indicator
      packet[2] = UInt8(pid & 0xFF)
      packet[3] = 0x10 | (continuityCounter & 0x0F)
      continuityCounter &+= 1
      cursor = 4
      write8(0) // pointer_field
    }

    mutating func beginSection(tableID: UInt8) {
      sectionStart = cursor
      write8(tableID)
      sectionLengthOffset = cursor
      write16(0) // section_length, patched by finishSection
    }

    mutating func finishSection() {
      let sectionLength = UInt16(cursor - (sectionLengthOffset + 2) + 4)
      packet[sectionLengthOffset] = 0xB0 | UInt8((sectionLength >> 8) & 0x0F)
      packet[sectionLengthOffset + 1] = UInt8(sectionLength & 0xFF)
      write32(MPEGTS.crc32(packet[sectionStart..<cursor]))
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
      write16(UInt16((value >> 16) & 0xFFFF))
      write16(UInt16(value & 0xFFFF))
    }

    mutating func writePID(_ pid: UInt16) {
      write8(0xE0 | UInt8((pid >> 8) & 0x1F))
      write8(UInt8(pid & 0xFF))
    }

    mutating func writeLength12(_ length: UInt16) {
      write8(0xF0 | UInt8((length >> 8) & 0x0F))
      write8(UInt8(length & 0xFF))
    }

    var data: Data {
      Data(packet)
    }
  }

  /// The program association table: one program, whose map is on `PID.pmt`.
  static func patPacket(continuityCounter: inout UInt8) -> Data {
    var writer = SectionPacketWriter(pid: PID.pat, continuityCounter: &continuityCounter)
    writer.beginSection(tableID: 0x00)
    writer.write16(0x0001) // transport_stream_id
    writer.write8(0xC1) // version 0, current_next_indicator
    writer.write8(0x00) // section_number
    writer.write8(0x00) // last_section_number
    writer.write16(0x0001) // program_number
    writer.writePID(PID.pmt)
    writer.finishSection()
    return writer.data
  }

  /// The program map table for the video stream, and the timed-metadata stream when included.
  static func pmtPacket(continuityCounter: inout UInt8, videoStreamType: UInt8, includeTimedMetadata: Bool) -> Data {
    var writer = SectionPacketWriter(pid: PID.pmt, continuityCounter: &continuityCounter)
    writer.beginSection(tableID: 0x02)
    writer.write16(0x0001) // program_number
    writer.write8(0xC1) // version 0, current_next_indicator
    writer.write8(0x00) // section_number
    writer.write8(0x00) // last_section_number
    writer.writePID(PID.video) // PCR_PID
    writer.writeLength12(0) // program_info_length
    writer.write8(videoStreamType)
    writer.writePID(PID.video)
    writer.writeLength12(0) // ES_info_length
    if includeTimedMetadata {
      writer.write8(StreamType.timedMetadata)
      writer.writePID(PID.timedMetadata)
      writer.writeLength12(0)
    }
    writer.finishSection()
    return writer.data
  }

  // MARK: - PES

  /// A PES header: start code, stream id, packet length, then PTS (and DTS when given) in the 33-bit
  /// 5-byte encoding. `packetLength` is the value of the `PES_packet_length` field; 0 means unbounded.
  private static func pesHeader(streamID: UInt8, packetLength: UInt16, pts90k: UInt64, dts90k: UInt64?) -> [UInt8] {
    var header: [UInt8] = [
      0x00, 0x00, 0x01, streamID,
      UInt8((packetLength >> 8) & 0xFF), UInt8(packetLength & 0xFF),
      0x80, // marker bits
      dts90k == nil ? 0x80 : 0xC0, // PTS_DTS_flags
      dts90k == nil ? 0x05 : 0x0A, // PES_header_data_length
    ]
    header.append(contentsOf: timestamp(pts90k, indicator: dts90k == nil ? 0x2 : 0x3))
    if let dts90k {
      header.append(contentsOf: timestamp(dts90k, indicator: 0x1))
    }
    return header
  }

  /// The 5-byte PTS/DTS field: a 4-bit indicator, then the 33-bit value split 3/15/15 with marker bits.
  private static func timestamp(_ value90k: UInt64, indicator: UInt8) -> [UInt8] {
    [
      (indicator << 4) | UInt8(truncatingIfNeeded: (value90k >> 29) & 0x0E) | 0x01,
      UInt8(truncatingIfNeeded: (value90k >> 22) & 0xFF),
      UInt8(truncatingIfNeeded: ((value90k >> 14) & 0xFE) | 0x01),
      UInt8(truncatingIfNeeded: (value90k >> 7) & 0xFF),
      UInt8(truncatingIfNeeded: ((value90k << 1) & 0xFE) | 0x01),
    ]
  }

  /// `PES_packet_length` for a packet of `totalLength` bytes: the bytes after the 6-byte prefix, or 0
  /// (unbounded) when they do not fit the 16-bit field.
  private static func pesPacketLength(totalLength: Int) -> UInt16 {
    totalLength - 6 <= 0xFFFF ? UInt16(totalLength - 6) : 0
  }

  /// One transport packet carrying the next slice of a PES payload. The first packet of a PES may
  /// carry a PCR; a packet that would not be filled is padded with an adaptation-field stuffing run.
  private static func pesPayloadPacket(
    pid: UInt16,
    payloadUnitStart: Bool,
    continuityCounter: inout UInt8,
    payload: [UInt8],
    payloadOffset: inout Int,
    pcr90k: UInt64?
  ) -> [UInt8] {
    var packet = [UInt8](repeating: 0xFF, count: packetSize)
    packet[0] = syncByte
    packet[1] = (payloadUnitStart ? 0x40 : 0x00) | UInt8((pid >> 8) & 0x1F)
    packet[2] = UInt8(pid & 0xFF)

    var headerSize = 4
    let remaining = payload.count - payloadOffset

    if let pcr90k {
      packet[3] = 0x30 | (continuityCounter & 0x0F) // adaptation field + payload
      packet[4] = 0x07 // adaptation_field_length
      packet[5] = 0x10 // PCR_flag
      packet[6] = UInt8(truncatingIfNeeded: pcr90k >> 25)
      packet[7] = UInt8(truncatingIfNeeded: pcr90k >> 17)
      packet[8] = UInt8(truncatingIfNeeded: pcr90k >> 9)
      packet[9] = UInt8(truncatingIfNeeded: pcr90k >> 1)
      packet[10] = UInt8(truncatingIfNeeded: ((pcr90k & 1) << 7) | 0x7E)
      packet[11] = 0x00
      headerSize = 12

      if remaining < payloadCapacityWithPCR {
        let stuffing = payloadCapacityWithPCR - remaining
        packet[4] = UInt8(0x07 + stuffing)
        headerSize += stuffing
      }
    } else if remaining < payloadCapacity {
      let stuffing = payloadCapacity - remaining
      packet[3] = 0x30 | (continuityCounter & 0x0F)
      if stuffing == 1 {
        packet[4] = 0x00
        headerSize = 5
      } else {
        packet[4] = UInt8(stuffing - 1)
        packet[5] = 0x00
        headerSize += stuffing
      }
    } else {
      packet[3] = 0x10 | (continuityCounter & 0x0F) // payload only
    }

    continuityCounter &+= 1
    let payloadSize = min(packetSize - headerSize, remaining)
    for k in 0..<payloadSize {
      packet[headerSize + k] = payload[payloadOffset + k]
    }
    payloadOffset += payloadSize
    return packet
  }

  /// Splits a PES packet across transport packets on `pid`, the first carrying `pcr90k` when given.
  private static func packetize(_ pes: [UInt8], pid: UInt16, continuityCounter: inout UInt8, pcr90k: UInt64?, into output: inout Data) {
    var offset = 0
    var first = true
    while offset < pes.count {
      let packet = pesPayloadPacket(
        pid: pid,
        payloadUnitStart: first,
        continuityCounter: &continuityCounter,
        payload: pes,
        payloadOffset: &offset,
        pcr90k: first ? pcr90k : nil)
      first = false
      output.append(contentsOf: packet)
    }
  }

  /// The transport packets for one video access unit. A keyframe is preceded by the PAT and PMT so a
  /// consumer can join mid-stream; the first video packet carries the PCR.
  static func videoPackets(
    accessUnit: [UInt8],
    isKeyFrame: Bool,
    videoStreamType: UInt8,
    pts90k: UInt64,
    videoContinuityCounter: inout UInt8,
    patContinuityCounter: inout UInt8,
    pmtContinuityCounter: inout UInt8
  ) -> Data {
    var pes = pesHeader(streamID: StreamID.video, packetLength: pesPacketLength(totalLength: 19 + accessUnit.count), pts90k: pts90k, dts90k: pts90k)
    pes.append(contentsOf: accessUnit)

    let firstPayload = min(pes.count, payloadCapacityWithPCR)
    let videoPacketCount = 1 + (pes.count - firstPayload + payloadCapacity - 1) / payloadCapacity
    var output = Data(capacity: ((isKeyFrame ? 2 : 0) + videoPacketCount) * packetSize)

    if isKeyFrame {
      output.append(patPacket(continuityCounter: &patContinuityCounter))
      output.append(pmtPacket(continuityCounter: &pmtContinuityCounter, videoStreamType: videoStreamType, includeTimedMetadata: true))
    }
    packetize(pes, pid: PID.video, continuityCounter: &videoContinuityCounter, pcr90k: pts90k, into: &output)
    return output
  }

  /// The transport packets for one timed-metadata marker: an ID3v2.4 tag holding a single `TXXX`
  /// frame with the text, in a private-stream PES on `PID.timedMetadata`.
  static func timedMetadataPackets(text: String, pts90k: UInt64, continuityCounter: inout UInt8) -> Data {
    let textBytes = [UInt8](text.utf8)
    let txxxPayloadLength = 1 + 1 + textBytes.count // encoding + empty description + text
    let id3PayloadLength = 10 + txxxPayloadLength // TXXX frame header + payload

    var id3 = [UInt8]()
    id3.reserveCapacity(10 + id3PayloadLength)
    id3.append(contentsOf: [
      UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3"),
      0x04, 0x00, // version 2.4
      0x00, // flags
      // size: syncsafe integer
      UInt8((id3PayloadLength >> 21) & 0x7F),
      UInt8((id3PayloadLength >> 14) & 0x7F),
      UInt8((id3PayloadLength >> 7) & 0x7F),
      UInt8(id3PayloadLength & 0x7F),
    ])
    id3.append(contentsOf: [
      UInt8(ascii: "T"), UInt8(ascii: "X"), UInt8(ascii: "X"), UInt8(ascii: "X"),
      UInt8((txxxPayloadLength >> 24) & 0xFF),
      UInt8((txxxPayloadLength >> 16) & 0xFF),
      UInt8((txxxPayloadLength >> 8) & 0xFF),
      UInt8(txxxPayloadLength & 0xFF),
      0x00, 0x00, // flags
      0x03, // UTF-8
      0x00, // empty description
    ])
    id3.append(contentsOf: textBytes)

    var pes = pesHeader(streamID: StreamID.privateStream1, packetLength: pesPacketLength(totalLength: 14 + id3.count), pts90k: pts90k, dts90k: nil)
    pes.append(contentsOf: id3)

    var output = Data(capacity: ((pes.count + payloadCapacity - 1) / payloadCapacity) * packetSize)
    packetize(pes, pid: PID.timedMetadata, continuityCounter: &continuityCounter, pcr90k: nil, into: &output)
    return output
  }
}

extension VideoStreamCodec {
  var mpegtsStreamType: UInt8 {
    switch self {
    case .h264:
      return MPEGTS.StreamType.h264
    case .hevc:
      return MPEGTS.StreamType.hevc
    }
  }
}

// MARK: - MPEGTSFrameWriter

/// Frames each encoded sample as an MPEG-TS access unit, with the program tables ahead of every
/// keyframe. The program map always declares the timed-metadata stream, so a marker written at any
/// point — including before the first keyframe — travels on a PID every demuxer already knows about.
///
/// Frames arrive on the encoder's output thread and markers from other threads; the state they
/// share — the last video PTS a marker is stamped with, and the metadata continuity counter — lives
/// under one `OSAllocatedUnfairLock`. The video and table counters are touched only from `write`.
public final class MPEGTSFrameWriter: EncodedFrameWriter, VideoStreamTimedMetadataWriter {
  private struct MetadataState {
    var continuityCounter: UInt8 = 0
    var lastPts90k: UInt64 = 0
  }

  private let codec: VideoStreamCodec
  private let metadata = OSAllocatedUnfairLock(initialState: MetadataState())
  private var videoContinuityCounter: UInt8 = 0
  private var patContinuityCounter: UInt8 = 0
  private var pmtContinuityCounter: UInt8 = 0

  public init(codec: VideoStreamCodec) {
    self.codec = codec
  }

  public func write(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) throws {
    if !CMSampleBufferDataIsReady(sampleBuffer) {
      throw EncodedFrameWriterError.sampleBufferNotReady
    }

    let isKeyFrame = sampleBuffer.isKeyFrame

    // AVCC length prefixes and Annex-B start codes are both 4 bytes, so sizes are unchanged by the conversion.
    try AnnexB.replaceLengthPrefixes(in: sampleBuffer)

    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw EncodedFrameWriterError.failedToGetDataBuffer
    }

    // The access unit: parameter sets ahead of a keyframe, then the NAL data.
    var accessUnit = Data()
    if isKeyFrame {
      guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        throw EncodedFrameWriterError.failedToGetFormatDescription
      }
      for parameterSet in try format.parameterSets(for: codec) {
        accessUnit.append(contentsOf: AnnexB.startCode)
        accessUnit.append(contentsOf: parameterSet)
      }
    }
    try dataBuffer.appendBytes(to: &accessUnit)

    let pts90k = UInt64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 90000.0)
    metadata.withLock { $0.lastPts90k = pts90k }

    consumer.consumeData(
      MPEGTS.videoPackets(
        accessUnit: [UInt8](accessUnit),
        isKeyFrame: isKeyFrame,
        videoStreamType: codec.mpegtsStreamType,
        pts90k: pts90k,
        videoContinuityCounter: &videoContinuityCounter,
        patContinuityCounter: &patContinuityCounter,
        pmtContinuityCounter: &pmtContinuityCounter))
  }

  public func writeTimedMetadata(_ text: String, to consumer: any DataConsumer) {
    let packets = metadata.withLock { state in
      MPEGTS.timedMetadataPackets(text: text, pts90k: state.lastPts90k, continuityCounter: &state.continuityCounter)
    }
    consumer.consumeData(packets)
  }
}
