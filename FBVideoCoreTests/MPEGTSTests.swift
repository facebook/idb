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

/// MPEG-TS packetisation (`MPEGTS`) and the frame writer built on it.
@Suite
struct MPEGTSTests {

  // MARK: - MPEG-TS CRC32

  @Test
  func mpegtsCRC32KnownVector() {
    // MPEG-2 CRC32 of "123456789" is a well-known test vector
    let data: [UInt8] = [UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "3"), UInt8(ascii: "4"), UInt8(ascii: "5"), UInt8(ascii: "6"), UInt8(ascii: "7"), UInt8(ascii: "8"), UInt8(ascii: "9")]
    let crc = MPEGTS.crc32(data)
    #expect(crc == 0x0376E6E7)
  }

  // MARK: - MPEG-TS PAT/PMT Structure

  @Test
  func patPacketStructure() {
    var counter: UInt8 = 0
    let pat = MPEGTS.patPacket(continuityCounter: &counter)

    #expect(pat.count == 188)

    let bytes = [UInt8](pat)

    // Sync byte
    #expect(bytes[0] == 0x47)

    // PID = 0x0000 (PAT), payload_unit_start = 1
    let pid = UInt16((bytes[1] & 0x1F)) << 8 | UInt16(bytes[2])
    #expect(pid == 0x0000)
    #expect((bytes[1] & 0x40) != 0) // payload_unit_start

    // Pointer field
    #expect(bytes[4] == 0x00)

    // table_id = 0x00 (PAT)
    #expect(bytes[5] == 0x00)

    // Program number = 1 at section offset 8-9
    let section = Array(bytes[5...])
    let programNumber = UInt16(section[8]) << 8 | UInt16(section[9])
    #expect(programNumber == 1)

    // PMT PID = 0x0100 at section offset 10-11
    let pmtPid = UInt16(section[10] & 0x1F) << 8 | UInt16(section[11])
    #expect(pmtPid == 0x0100)

    #expect(counter == 1)
  }

  @Test
  func pmtPacketStructureHEVC() {
    var counter: UInt8 = 0
    let pmt = MPEGTS.pmtPacket(continuityCounter: &counter, videoStreamType: 0x24, includeTimedMetadata: false)

    #expect(pmt.count == 188)

    let bytes = [UInt8](pmt)

    // Sync byte
    #expect(bytes[0] == 0x47)

    // PID = 0x0100 (PMT), payload_unit_start = 1
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    #expect(pid == 0x0100)
    #expect((bytes[1] & 0x40) != 0) // payload_unit_start

    // table_id = 0x02 (PMT)
    #expect(bytes[5] == 0x02)

    // Stream entry: stream_type = 0x24 (HEVC) at section offset 12
    let section = Array(bytes[5...])
    #expect(section[12] == 0x24)

    // Elementary PID = 0x0101 at section offset 13-14
    let elementaryPid = UInt16(section[13] & 0x1F) << 8 | UInt16(section[14])
    #expect(elementaryPid == 0x0101)

    #expect(counter == 1)
  }

  @Test
  func patContinuityCounterIncrements() {
    var counter: UInt8 = 0
    _ = MPEGTS.patPacket(continuityCounter: &counter)
    #expect(counter == 1)
    _ = MPEGTS.patPacket(continuityCounter: &counter)
    #expect(counter == 2)
  }

  // MARK: - MPEG-TS Packetization

  @Test
  func tsPacketizationSinglePacket() {
    // Small PES payload that fits in one TS packet (< 184 bytes)
    var pesBytes = [UInt8](repeating: 0xAB, count: 100)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: false, videoStreamType: 0x24, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    // Non-keyframe: no PAT/PMT, just one video TS packet
    #expect(output.count == 188)

    let bytes = Array(output)

    // Sync byte
    #expect(bytes[0] == 0x47)

    // payload_unit_start = 1 (first packet)
    #expect((bytes[1] & 0x40) != 0)

    // Video PID = 0x0101
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    #expect(pid == 0x0101)

    // First packet should have adaptation field with PCR
    #expect(bytes[3] & 0x30 == 0x30) // adaptation + payload
    #expect((bytes[5] & 0x10) != 0) // PCR flag set
  }

  @Test
  func tsPacketizationMultiplePackets() {
    // PES payload > 184 bytes to require multiple TS packets
    var pesBytes = [UInt8](repeating: 0xCD, count: 300)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: false, videoStreamType: 0x24, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    #expect(output.count == 188 * 2)

    let bytes = Array(output)

    // First packet: payload_unit_start = 1
    #expect(bytes[0] == 0x47)
    #expect((bytes[1] & 0x40) != 0)

    // Second packet: payload_unit_start = 0
    #expect(bytes[188] == 0x47)
    #expect((bytes[189] & 0x40) == 0)
  }

  @Test
  func tsPacketizationKeyframeEmitsPATAndPMT() {
    var pesBytes = [UInt8](repeating: 0xEF, count: 50)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: true, videoStreamType: 0x24, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    // Keyframe: PAT + PMT + 1 video packet = 3 * 188 = 564
    #expect(output.count == 188 * 3)

    let bytes = Array(output)

    // First packet is PAT (PID = 0x0000)
    #expect(bytes[0] == 0x47)
    let pid0 = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    #expect(pid0 == 0x0000)

    // Second packet is PMT (PID = 0x0100)
    #expect(bytes[188] == 0x47)
    let pid1 = UInt16(bytes[189] & 0x1F) << 8 | UInt16(bytes[190])
    #expect(pid1 == 0x0100)

    // Third packet is video (PID = 0x0101)
    #expect(bytes[376] == 0x47)
    let pid2 = UInt16(bytes[377] & 0x1F) << 8 | UInt16(bytes[378])
    #expect(pid2 == 0x0101)
  }

  @Test
  func tsPacketizationNonKeyframeNoPATOrPMT() {
    var pesBytes = [UInt8](repeating: 0xEF, count: 50)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: false, videoStreamType: 0x24, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    // Non-keyframe: just 1 video packet
    #expect(output.count == 188)

    let bytes = Array(output)

    // First (and only) packet is video (PID = 0x0101), not PAT/PMT
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    #expect(pid == 0x0101)

    #expect(patCC == 0)
    #expect(pmtCC == 0)
  }

  @Test
  func tsPacketizationKeyframeUsesH264StreamType() {
    var pesBytes = [UInt8](repeating: 0xEF, count: 50)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: true, videoStreamType: 0x1B, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    // Keyframe: PAT + PMT + 1 video packet = 3 * 188 = 564
    #expect(output.count == 188 * 3)

    let bytes = Array(output)

    // Second packet is PMT (PID = 0x0100)
    #expect(bytes[188] == 0x47)

    // Verify PMT contains H264 stream type (0x1B) in the stream entry
    let pmtSection = Array(bytes[(188 + 5)...])
    #expect(pmtSection[12] == 0x1B)
  }

  // MARK: - MPEG-TS PMT with Metadata

  @Test
  func pmtWithMetadataStreamContainsTwoEntries() {
    var counter: UInt8 = 0
    let pmt = MPEGTS.pmtPacket(continuityCounter: &counter, videoStreamType: 0x24, includeTimedMetadata: true)

    #expect(pmt.count == 188)

    let bytes = [UInt8](pmt)

    // Sync byte and PID = 0x0100
    #expect(bytes[0] == 0x47)
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    #expect(pid == 0x0100)

    // table_id = 0x02 (PMT)
    #expect(bytes[5] == 0x02)

    let section = Array(bytes[5...])

    // Video stream entry at offset 12: stream_type = 0x24
    #expect(section[12] == 0x24)
    let videoPid = UInt16(section[13] & 0x1F) << 8 | UInt16(section[14])
    #expect(videoPid == 0x0101)

    // Metadata stream entry at offset 17: stream_type = 0x15
    #expect(section[17] == 0x15)
    let metaPid = UInt16(section[18] & 0x1F) << 8 | UInt16(section[19])
    #expect(metaPid == MPEGTS.PID.timedMetadata)
  }

  // MARK: - MPEG-TS Timed Metadata Packets

  @Test
  func timedMetadataPacketStructure() {
    var counter: UInt8 = 0
    let output = MPEGTS.timedMetadataPackets(text: "Chapter 1", pts90k: 90000, continuityCounter: &counter)

    #expect(output.count > 0)
    #expect(output.count % 188 == 0)

    let bytes = Array(output)

    // Sync byte
    #expect(bytes[0] == 0x47)

    // payload_unit_start = 1
    #expect((bytes[1] & 0x40) != 0)

    // PID = MetadataPID (0x0102)
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    #expect(pid == MPEGTS.PID.timedMetadata)

    #expect(counter == 1)

    // Find PES start code with private_stream_1 (0xBD)
    let pesStartCode = Data([0x00, 0x00, 0x01, 0xBD])
    let pesRange = (output as NSData).range(of: pesStartCode, options: [], in: NSRange(location: 0, length: output.count))
    #expect(pesRange.location != NSNotFound, "PES start code with private_stream_1 should be present")

    let id3Header = Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3")])
    let id3Range = (output as NSData).range(of: id3Header, options: [], in: NSRange(location: 0, length: output.count))
    #expect(id3Range.location != NSNotFound, "ID3 header should be present")

    let txxxFrame = Data([UInt8(ascii: "T"), UInt8(ascii: "X"), UInt8(ascii: "X"), UInt8(ascii: "X")])
    let txxxRange = (output as NSData).range(of: txxxFrame, options: [], in: NSRange(location: 0, length: output.count))
    #expect(txxxRange.location != NSNotFound, "TXXX frame should be present")

    let chapterText = "Chapter 1".data(using: .utf8)!
    let textRange = (output as NSData).range(of: chapterText, options: [], in: NSRange(location: 0, length: output.count))
    #expect(textRange.location != NSNotFound, "Chapter text should be present in output")
  }

  @Test
  func timedMetadataShortTextFitsInOnePacket() {
    var counter: UInt8 = 0
    let output = MPEGTS.timedMetadataPackets(text: "Hi", pts90k: 0, continuityCounter: &counter)
    #expect(output.count == 188)
  }

  @Test
  func timedMetadataLongTextSpansMultiplePackets() {
    var longText = ""
    for _ in 0..<50 {
      longText.append("ABCDEFGHIJ")
    }
    var counter: UInt8 = 0
    let output = MPEGTS.timedMetadataPackets(text: longText, pts90k: 45000, continuityCounter: &counter)
    #expect(output.count > 188)
    #expect(output.count % 188 == 0)

    let bytes = Array(output)
    let numPackets = output.count / 188
    for i in 0..<numPackets {
      #expect(bytes[i * 188] == 0x47, "Packet \(i) should have sync byte")
      let pktPid = UInt16(bytes[i * 188 + 1] & 0x1F) << 8 | UInt16(bytes[i * 188 + 2])
      #expect(pktPid == MPEGTS.PID.timedMetadata, "Packet \(i) should have metadata PID")
    }

    #expect((bytes[1] & 0x40) != 0, "First packet should have payload_unit_start")
    if numPackets > 1 {
      #expect((bytes[189] & 0x40) == 0, "Second packet should not have payload_unit_start")
    }
  }

  // MARK: - MPEG-TS Frame Writer (full pipeline)

  @Test
  func h264MPEGTSFrameWriterKeyframeIsWellFormed() {
    let sampleBuffer = makeH264SampleBuffer(isKeyFrame: true)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MPEGTSFrameWriter(codec: .h264)

    #expect(throws: Never.self) { try writer.write(sampleBuffer, to: consumer, logger: logger) }

    let output = consumer.data()
    #expect(output.count > 0)
    #expect(output.count % 188 == 0, "Output must be whole 188-byte TS packets")

    let bytes = [UInt8](output)
    var i = 0
    while i + 188 <= bytes.count {
      #expect(bytes[i] == 0x47, "Packet at offset \(i) missing sync byte")
      i += 188
    }

    // A keyframe emits PAT (0x0000) + PMT (0x0100) for mid-stream join, plus video (0x0101).
    let pids = Set(tsPacketPIDs(output))
    #expect(pids.contains(0x0000), "Keyframe should emit a PAT")
    #expect(pids.contains(0x0100), "Keyframe should emit a PMT")
    #expect(pids.contains(0x0101), "Should emit video packets")
  }

  @Test
  func h264MPEGTSFrameWriterNotReadyThrows() throws {
    let sampleBuffer = makeNotReadySampleBuffer()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MPEGTSFrameWriter(codec: .h264)

    let error = #expect(throws: (any Error).self) { try writer.write(sampleBuffer, to: consumer, logger: logger) }
    #expect(error?.localizedDescription.contains("Sample Buffer is not ready") == true)
    #expect(consumer.data().count == 0, "No data should be written for not-ready buffer")
  }

  @Test
  func hevcMPEGTSStreamKeyframeUsesHEVCStreamType() throws {
    let sampleBuffer = try #require(makeHEVCSampleBuffer(isKeyFrame: true))
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MPEGTSFrameWriter(codec: .hevc)

    #expect(throws: Never.self) { try writer.write(sampleBuffer, to: consumer, logger: logger) }

    let output = consumer.data()
    #expect(output.count % 188 == 0)

    // Locate the PMT packet (PID 0x0100) and assert the video stream_type is HEVC (0x24).
    // PMT packets have no adaptation field, so the section begins at the 5th byte
    // (4-byte TS header + 1-byte pointer field) and section[12] is the stream_type.
    let bytes = [UInt8](output)
    var foundPMT = false
    var i = 0
    while i + 188 <= bytes.count {
      let pid = (UInt16(bytes[i + 1] & 0x1F) << 8) | UInt16(bytes[i + 2])
      if pid == 0x0100 {
        #expect(bytes[i + 5 + 12] == 0x24, "HEVC PMT video stream_type should be 0x24")
        foundPMT = true
      }
      i += 188
    }
    #expect(foundPMT, "Keyframe should emit a PMT")
  }

  // MARK: - MPEG-TS Program Map

  @Test
  func mpegtsKeyframePMTAlwaysDeclaresTheMetadataStream() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    try MPEGTSFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: true), to: consumer, logger: ControlCoreLoggerDouble())

    let pmt = try #require(tsPackets(consumer.data(), pid: 0x0100).first)
    var counter: UInt8 = 0
    let expectedPMT = MPEGTS.pmtPacket(continuityCounter: &counter, videoStreamType: 0x1B, includeTimedMetadata: true)
    #expect(pmt == expectedPMT)
  }

  // MARK: - MPEG-TS Timed Metadata Stream

  @Test
  func enableMetadataStreamThenWriteTimedMetadataEmitsOnMetadataPID() {
    let writer = MPEGTSFrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    writer.writeTimedMetadata("Chapter Zulu", to: consumer)

    let output = consumer.data()
    #expect(output.count > 0, "Enabled metadata stream should emit packets")
    #expect(output.count % 188 == 0)

    let bytes = [UInt8](output)
    var i = 0
    while i + 188 <= bytes.count {
      #expect(bytes[i] == 0x47)
      let pid = (UInt16(bytes[i + 1] & 0x1F) << 8) | UInt16(bytes[i + 2])
      #expect(pid == MPEGTS.PID.timedMetadata, "Timed metadata must be on the metadata PID")
      i += 188
    }

    let id3 = (output as NSData).range(of: Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3")]), options: [], in: NSRange(location: 0, length: output.count))
    #expect(id3.location != NSNotFound, "ID3 header should be present")
    let text = (output as NSData).range(of: "Chapter Zulu".data(using: .utf8)!, options: [], in: NSRange(location: 0, length: output.count))
    #expect(text.location != NSNotFound, "Chapter text should be present")
  }
}
