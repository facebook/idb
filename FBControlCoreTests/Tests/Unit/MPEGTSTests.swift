/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBControlCore
import XCTest

/// MPEG-TS packetisation (`MPEGTS`) and the frame writer built on it.
final class MPEGTSTests: XCTestCase {

  // MARK: - MPEG-TS CRC32

  func testMPEGTSCRC32KnownVector() {
    // MPEG-2 CRC32 of "123456789" is a well-known test vector
    let data: [UInt8] = [UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "3"), UInt8(ascii: "4"), UInt8(ascii: "5"), UInt8(ascii: "6"), UInt8(ascii: "7"), UInt8(ascii: "8"), UInt8(ascii: "9")]
    let crc = MPEGTS.crc32(data)
    XCTAssertEqual(crc, 0x0376E6E7)
  }

  // MARK: - MPEG-TS PAT/PMT Structure

  func testPATPacketStructure() {
    var counter: UInt8 = 0
    let pat = MPEGTS.patPacket(continuityCounter: &counter)

    XCTAssertEqual(pat.count, 188)

    let bytes = [UInt8](pat)

    // Sync byte
    XCTAssertEqual(bytes[0], 0x47)

    // PID = 0x0000 (PAT), payload_unit_start = 1
    let pid = UInt16((bytes[1] & 0x1F)) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid, 0x0000)
    XCTAssertTrue((bytes[1] & 0x40) != 0) // payload_unit_start

    // Pointer field
    XCTAssertEqual(bytes[4], 0x00)

    // table_id = 0x00 (PAT)
    XCTAssertEqual(bytes[5], 0x00)

    // Program number = 1 at section offset 8-9
    let section = Array(bytes[5...])
    let programNumber = UInt16(section[8]) << 8 | UInt16(section[9])
    XCTAssertEqual(programNumber, 1)

    // PMT PID = 0x0100 at section offset 10-11
    let pmtPid = UInt16(section[10] & 0x1F) << 8 | UInt16(section[11])
    XCTAssertEqual(pmtPid, 0x0100)

    XCTAssertEqual(counter, 1)
  }

  func testPMTPacketStructureHEVC() {
    var counter: UInt8 = 0
    let pmt = MPEGTS.pmtPacket(continuityCounter: &counter, videoStreamType: 0x24, includeTimedMetadata: false)

    XCTAssertEqual(pmt.count, 188)

    let bytes = [UInt8](pmt)

    // Sync byte
    XCTAssertEqual(bytes[0], 0x47)

    // PID = 0x0100 (PMT), payload_unit_start = 1
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid, 0x0100)
    XCTAssertTrue((bytes[1] & 0x40) != 0) // payload_unit_start

    // table_id = 0x02 (PMT)
    XCTAssertEqual(bytes[5], 0x02)

    // Stream entry: stream_type = 0x24 (HEVC) at section offset 12
    let section = Array(bytes[5...])
    XCTAssertEqual(section[12], 0x24)

    // Elementary PID = 0x0101 at section offset 13-14
    let elementaryPid = UInt16(section[13] & 0x1F) << 8 | UInt16(section[14])
    XCTAssertEqual(elementaryPid, 0x0101)

    XCTAssertEqual(counter, 1)
  }

  func testPATContinuityCounterIncrements() {
    var counter: UInt8 = 0
    _ = MPEGTS.patPacket(continuityCounter: &counter)
    XCTAssertEqual(counter, 1)
    _ = MPEGTS.patPacket(continuityCounter: &counter)
    XCTAssertEqual(counter, 2)
  }

  // MARK: - MPEG-TS Packetization

  func testTSPacketizationSinglePacket() {
    // Small PES payload that fits in one TS packet (< 184 bytes)
    var pesBytes = [UInt8](repeating: 0xAB, count: 100)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: false, videoStreamType: 0x24, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    // Non-keyframe: no PAT/PMT, just one video TS packet
    XCTAssertEqual(output.count, 188)

    let bytes = Array(output)

    // Sync byte
    XCTAssertEqual(bytes[0], 0x47)

    // payload_unit_start = 1 (first packet)
    XCTAssertTrue((bytes[1] & 0x40) != 0)

    // Video PID = 0x0101
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid, 0x0101)

    // First packet should have adaptation field with PCR
    XCTAssertEqual(bytes[3] & 0x30, 0x30) // adaptation + payload
    XCTAssertTrue((bytes[5] & 0x10) != 0) // PCR flag set
  }

  func testTSPacketizationMultiplePackets() {
    // PES payload > 184 bytes to require multiple TS packets
    var pesBytes = [UInt8](repeating: 0xCD, count: 300)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: false, videoStreamType: 0x24, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    XCTAssertEqual(output.count, 188 * 2)

    let bytes = Array(output)

    // First packet: payload_unit_start = 1
    XCTAssertEqual(bytes[0], 0x47)
    XCTAssertTrue((bytes[1] & 0x40) != 0)

    // Second packet: payload_unit_start = 0
    XCTAssertEqual(bytes[188], 0x47)
    XCTAssertFalse((bytes[189] & 0x40) != 0)
  }

  func testTSPacketizationKeyframeEmitsPATAndPMT() {
    var pesBytes = [UInt8](repeating: 0xEF, count: 50)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: true, videoStreamType: 0x24, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    // Keyframe: PAT + PMT + 1 video packet = 3 * 188 = 564
    XCTAssertEqual(output.count, 188 * 3)

    let bytes = Array(output)

    // First packet is PAT (PID = 0x0000)
    XCTAssertEqual(bytes[0], 0x47)
    let pid0 = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid0, 0x0000)

    // Second packet is PMT (PID = 0x0100)
    XCTAssertEqual(bytes[188], 0x47)
    let pid1 = UInt16(bytes[189] & 0x1F) << 8 | UInt16(bytes[190])
    XCTAssertEqual(pid1, 0x0100)

    // Third packet is video (PID = 0x0101)
    XCTAssertEqual(bytes[376], 0x47)
    let pid2 = UInt16(bytes[377] & 0x1F) << 8 | UInt16(bytes[378])
    XCTAssertEqual(pid2, 0x0101)
  }

  func testTSPacketizationNonKeyframeNoPATOrPMT() {
    var pesBytes = [UInt8](repeating: 0xEF, count: 50)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: false, videoStreamType: 0x24, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    // Non-keyframe: just 1 video packet
    XCTAssertEqual(output.count, 188)

    let bytes = Array(output)

    // First (and only) packet is video (PID = 0x0101), not PAT/PMT
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid, 0x0101)

    XCTAssertEqual(patCC, 0)
    XCTAssertEqual(pmtCC, 0)
  }

  func testTSPacketizationKeyframeUsesH264StreamType() {
    var pesBytes = [UInt8](repeating: 0xEF, count: 50)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = MPEGTS.videoPackets(accessUnit: [UInt8](pesData), isKeyFrame: true, videoStreamType: 0x1B, pts90k: 90000, videoContinuityCounter: &videoCC, patContinuityCounter: &patCC, pmtContinuityCounter: &pmtCC)

    // Keyframe: PAT + PMT + 1 video packet = 3 * 188 = 564
    XCTAssertEqual(output.count, 188 * 3)

    let bytes = Array(output)

    // Second packet is PMT (PID = 0x0100)
    XCTAssertEqual(bytes[188], 0x47)

    // Verify PMT contains H264 stream type (0x1B) in the stream entry
    let pmtSection = Array(bytes[(188 + 5)...])
    XCTAssertEqual(pmtSection[12], 0x1B)
  }

  // MARK: - MPEG-TS PMT with Metadata

  func testPMTWithMetadataStreamContainsTwoEntries() {
    var counter: UInt8 = 0
    let pmt = MPEGTS.pmtPacket(continuityCounter: &counter, videoStreamType: 0x24, includeTimedMetadata: true)

    XCTAssertEqual(pmt.count, 188)

    let bytes = [UInt8](pmt)

    // Sync byte and PID = 0x0100
    XCTAssertEqual(bytes[0], 0x47)
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid, 0x0100)

    // table_id = 0x02 (PMT)
    XCTAssertEqual(bytes[5], 0x02)

    let section = Array(bytes[5...])

    // Video stream entry at offset 12: stream_type = 0x24
    XCTAssertEqual(section[12], 0x24)
    let videoPid = UInt16(section[13] & 0x1F) << 8 | UInt16(section[14])
    XCTAssertEqual(videoPid, 0x0101)

    // Metadata stream entry at offset 17: stream_type = 0x15
    XCTAssertEqual(section[17], 0x15)
    let metaPid = UInt16(section[18] & 0x1F) << 8 | UInt16(section[19])
    XCTAssertEqual(metaPid, MPEGTS.PID.timedMetadata)
  }

  // MARK: - MPEG-TS Timed Metadata Packets

  func testTimedMetadataPacketStructure() {
    var counter: UInt8 = 0
    let output = MPEGTS.timedMetadataPackets(text: "Chapter 1", pts90k: 90000, continuityCounter: &counter)

    XCTAssertGreaterThan(output.count, 0)
    XCTAssertEqual(output.count % 188, 0)

    let bytes = Array(output)

    // Sync byte
    XCTAssertEqual(bytes[0], 0x47)

    // payload_unit_start = 1
    XCTAssertTrue((bytes[1] & 0x40) != 0)

    // PID = MetadataPID (0x0102)
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid, MPEGTS.PID.timedMetadata)

    XCTAssertEqual(counter, 1)

    // Find PES start code with private_stream_1 (0xBD)
    let pesStartCode = Data([0x00, 0x00, 0x01, 0xBD])
    let pesRange = (output as NSData).range(of: pesStartCode, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(pesRange.location, NSNotFound, "PES start code with private_stream_1 should be present")

    let id3Header = Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3")])
    let id3Range = (output as NSData).range(of: id3Header, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(id3Range.location, NSNotFound, "ID3 header should be present")

    let txxxFrame = Data([UInt8(ascii: "T"), UInt8(ascii: "X"), UInt8(ascii: "X"), UInt8(ascii: "X")])
    let txxxRange = (output as NSData).range(of: txxxFrame, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(txxxRange.location, NSNotFound, "TXXX frame should be present")

    let chapterText = "Chapter 1".data(using: .utf8)!
    let textRange = (output as NSData).range(of: chapterText, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(textRange.location, NSNotFound, "Chapter text should be present in output")
  }

  func testTimedMetadataShortTextFitsInOnePacket() {
    var counter: UInt8 = 0
    let output = MPEGTS.timedMetadataPackets(text: "Hi", pts90k: 0, continuityCounter: &counter)
    XCTAssertEqual(output.count, 188)
  }

  func testTimedMetadataLongTextSpansMultiplePackets() {
    var longText = ""
    for _ in 0..<50 {
      longText.append("ABCDEFGHIJ")
    }
    var counter: UInt8 = 0
    let output = MPEGTS.timedMetadataPackets(text: longText, pts90k: 45000, continuityCounter: &counter)
    XCTAssertGreaterThan(output.count, 188)
    XCTAssertEqual(output.count % 188, 0)

    let bytes = Array(output)
    let numPackets = output.count / 188
    for i in 0..<numPackets {
      XCTAssertEqual(bytes[i * 188], 0x47, "Packet \(i) should have sync byte")
      let pktPid = UInt16(bytes[i * 188 + 1] & 0x1F) << 8 | UInt16(bytes[i * 188 + 2])
      XCTAssertEqual(pktPid, MPEGTS.PID.timedMetadata, "Packet \(i) should have metadata PID")
    }

    XCTAssertTrue((bytes[1] & 0x40) != 0, "First packet should have payload_unit_start")
    if numPackets > 1 {
      XCTAssertFalse((bytes[189] & 0x40) != 0, "Second packet should not have payload_unit_start")
    }
  }

  // MARK: - MPEG-TS Frame Writer (full pipeline)

  func testH264MPEGTSFrameWriterKeyframeIsWellFormed() {
    let sampleBuffer = makeH264SampleBuffer(isKeyFrame: true)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MPEGTSFrameWriter(codec: .h264)

    XCTAssertNoThrow(try writer.write(sampleBuffer, to: consumer, logger: logger))

    let output = consumer.data()
    XCTAssertGreaterThan(output.count, 0)
    XCTAssertEqual(output.count % 188, 0, "Output must be whole 188-byte TS packets")

    let bytes = [UInt8](output)
    var i = 0
    while i + 188 <= bytes.count {
      XCTAssertEqual(bytes[i], 0x47, "Packet at offset \(i) missing sync byte")
      i += 188
    }

    // A keyframe emits PAT (0x0000) + PMT (0x0100) for mid-stream join, plus video (0x0101).
    let pids = Set(tsPacketPIDs(output))
    XCTAssertTrue(pids.contains(0x0000), "Keyframe should emit a PAT")
    XCTAssertTrue(pids.contains(0x0100), "Keyframe should emit a PMT")
    XCTAssertTrue(pids.contains(0x0101), "Should emit video packets")
  }

  func testH264MPEGTSFrameWriterNotReadyThrows() throws {
    let sampleBuffer = makeNotReadySampleBuffer()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MPEGTSFrameWriter(codec: .h264)

    XCTAssertThrowsError(try writer.write(sampleBuffer, to: consumer, logger: logger)) { error in
      XCTAssertTrue(error.localizedDescription.contains("Sample Buffer is not ready"))
    }
    XCTAssertEqual(consumer.data().count, 0, "No data should be written for not-ready buffer")
  }

  func testHEVCMPEGTSStreamKeyframeUsesHEVCStreamType() throws {
    let sampleBuffer = try XCTUnwrap(makeHEVCSampleBuffer(isKeyFrame: true))
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = MPEGTSFrameWriter(codec: .hevc)

    XCTAssertNoThrow(try writer.write(sampleBuffer, to: consumer, logger: logger))

    let output = consumer.data()
    XCTAssertEqual(output.count % 188, 0)

    // Locate the PMT packet (PID 0x0100) and assert the video stream_type is HEVC (0x24).
    // PMT packets have no adaptation field, so the section begins at the 5th byte
    // (4-byte TS header + 1-byte pointer field) and section[12] is the stream_type.
    let bytes = [UInt8](output)
    var foundPMT = false
    var i = 0
    while i + 188 <= bytes.count {
      let pid = (UInt16(bytes[i + 1] & 0x1F) << 8) | UInt16(bytes[i + 2])
      if pid == 0x0100 {
        XCTAssertEqual(bytes[i + 5 + 12], 0x24, "HEVC PMT video stream_type should be 0x24")
        foundPMT = true
      }
      i += 188
    }
    XCTAssertTrue(foundPMT, "Keyframe should emit a PMT")
  }

  // MARK: - MPEG-TS Program Map

  func testMPEGTSKeyframePMTAlwaysDeclaresTheMetadataStream() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    try MPEGTSFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: true), to: consumer, logger: ControlCoreLoggerDouble())

    let pmt = try XCTUnwrap(tsPackets(consumer.data(), pid: 0x0100).first)
    var counter: UInt8 = 0
    XCTAssertEqual(pmt, MPEGTS.pmtPacket(continuityCounter: &counter, videoStreamType: 0x1B, includeTimedMetadata: true))
  }

  // MARK: - MPEG-TS Timed Metadata Stream

  func testEnableMetadataStreamThenWriteTimedMetadataEmitsOnMetadataPID() {
    let writer = MPEGTSFrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    writer.writeTimedMetadata("Chapter Zulu", to: consumer)

    let output = consumer.data()
    XCTAssertGreaterThan(output.count, 0, "Enabled metadata stream should emit packets")
    XCTAssertEqual(output.count % 188, 0)

    let bytes = [UInt8](output)
    var i = 0
    while i + 188 <= bytes.count {
      XCTAssertEqual(bytes[i], 0x47)
      let pid = (UInt16(bytes[i + 1] & 0x1F) << 8) | UInt16(bytes[i + 2])
      XCTAssertEqual(pid, MPEGTS.PID.timedMetadata, "Timed metadata must be on the metadata PID")
      i += 188
    }

    let id3 = (output as NSData).range(of: Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3")]), options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(id3.location, NSNotFound, "ID3 header should be present")
    let text = (output as NSData).range(of: "Chapter Zulu".data(using: .utf8)!, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(text.location, NSNotFound, "Chapter text should be present")
  }
}
