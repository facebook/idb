/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBControlCore
import XCTest

// MARK: - Test Doubles

/**
 A test double conforming to FBDataConsumerAsync with a controllable unprocessedDataCount.
 Used to test checkConsumerBufferLimit overflow behavior.
 */
@objc class FBOverflownConsumerDouble: NSObject, FBDataConsumer, FBDataConsumerAsync {
  private var _unprocessedDataCount: Int = 0

  @objc func unprocessedDataCount() -> Int {
    return _unprocessedDataCount
  }

  func setUnprocessedDataCount(_ value: Int) {
    _unprocessedDataCount = value
  }

  @objc func consumeData(_ data: Data) {}

  @objc func consumeEndOfFile() {}
}

// MARK: - Helpers

private func CreateH264SampleBuffer(isKeyFrame: Bool) -> CMSampleBuffer {
  // H264 SPS and PPS parameter sets
  let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
  let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]
  let paramSizes: [Int] = [sps.count, pps.count]

  var formatDesc: CMFormatDescription?
  let status = sps.withUnsafeBufferPointer { spsPtr in
    pps.withUnsafeBufferPointer { ppsPtr in
      var paramSets: [UnsafePointer<UInt8>] = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
      return paramSets.withUnsafeBufferPointer { paramSetsPtr in
        paramSizes.withUnsafeBufferPointer { paramSizesPtr in
          CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: nil,
            parameterSetCount: 2,
            parameterSetPointers: paramSetsPtr.baseAddress!,
            parameterSetSizes: paramSizesPtr.baseAddress!,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &formatDesc
          )
        }
      }
    }
  }
  assert(status == noErr, "Failed to create H264 format description: \(status)")

  // AVCC NAL data: [4-byte big-endian length][NAL bytes]
  let avccBytes: [UInt8] = [
    0x00, 0x00, 0x00, 0x05, // NAL length = 5
    0x65, 0x88, 0x80, 0x40, 0x00, // fake IDR slice
  ]
  let avccDataCount = avccBytes.count
  // Allocate persistent memory that outlives the block buffer
  let avccPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: avccDataCount)
  avccBytes.withUnsafeBufferPointer { src in
    avccPtr.initialize(from: src.baseAddress!, count: avccDataCount)
  }

  var blockBuf: CMBlockBuffer?
  let blockStatus = CMBlockBufferCreateWithMemoryBlock(
    allocator: nil,
    memoryBlock: avccPtr,
    blockLength: avccDataCount,
    blockAllocator: kCFAllocatorNull,
    customBlockSource: nil,
    offsetToData: 0,
    dataLength: avccDataCount,
    flags: 0,
    blockBufferOut: &blockBuf
  )
  assert(blockStatus == noErr, "Failed to create block buffer: \(blockStatus)")

  var sampleBuf: CMSampleBuffer?
  var sampleSize = avccDataCount
  var timing = CMSampleTimingInfo(
    duration: CMTimeMake(value: 1, timescale: 30),
    presentationTimeStamp: CMTimeMake(value: 0, timescale: 90000),
    decodeTimeStamp: .invalid
  )
  let sampleStatus = CMSampleBufferCreate(
    allocator: nil,
    dataBuffer: blockBuf,
    dataReady: true,
    makeDataReadyCallback: nil,
    refcon: nil,
    formatDescription: formatDesc,
    sampleCount: 1,
    sampleTimingEntryCount: 1,
    sampleTimingArray: &timing,
    sampleSizeEntryCount: 1,
    sampleSizeArray: &sampleSize,
    sampleBufferOut: &sampleBuf
  )
  assert(sampleStatus == noErr, "Failed to create sample buffer: \(sampleStatus)")

  // Set attachments for keyframe/non-keyframe.
  // For keyframes: NotSync is absent (modern VideoToolbox pattern).
  // For non-keyframes: NotSync = kCFBooleanTrue.
  let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuf!, createIfNecessary: true)!
  let attachments = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFMutableDictionary.self)
  if !isKeyFrame {
    CFDictionarySetValue(
      attachments,
      Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
      Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
    )
  }

  return sampleBuf!
}

private func CreateNotReadySampleBuffer() -> CMSampleBuffer {
  // H264 SPS and PPS parameter sets
  let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
  let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]
  let paramSizes: [Int] = [sps.count, pps.count]

  var formatDesc: CMFormatDescription?
  let status = sps.withUnsafeBufferPointer { spsPtr in
    pps.withUnsafeBufferPointer { ppsPtr in
      var paramSets: [UnsafePointer<UInt8>] = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
      return paramSets.withUnsafeBufferPointer { paramSetsPtr in
        paramSizes.withUnsafeBufferPointer { paramSizesPtr in
          CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: nil,
            parameterSetCount: 2,
            parameterSetPointers: paramSetsPtr.baseAddress!,
            parameterSetSizes: paramSizesPtr.baseAddress!,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &formatDesc
          )
        }
      }
    }
  }
  assert(status == noErr, "Failed to create H264 format description: \(status)")

  // AVCC NAL data: [4-byte big-endian length][NAL bytes]
  let avccBytes: [UInt8] = [
    0x00, 0x00, 0x00, 0x05, // NAL length = 5
    0x65, 0x88, 0x80, 0x40, 0x00, // fake IDR slice
  ]
  let avccDataCount = avccBytes.count
  // Allocate persistent memory that outlives the block buffer
  let avccPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: avccDataCount)
  avccBytes.withUnsafeBufferPointer { src in
    avccPtr.initialize(from: src.baseAddress!, count: avccDataCount)
  }

  var blockBuf: CMBlockBuffer?
  let blockStatus = CMBlockBufferCreateWithMemoryBlock(
    allocator: nil,
    memoryBlock: avccPtr,
    blockLength: avccDataCount,
    blockAllocator: kCFAllocatorNull,
    customBlockSource: nil,
    offsetToData: 0,
    dataLength: avccDataCount,
    flags: 0,
    blockBufferOut: &blockBuf
  )
  assert(blockStatus == noErr, "Failed to create block buffer: \(blockStatus)")

  var sampleBuf: CMSampleBuffer?
  var sampleSize = avccDataCount
  var timing = CMSampleTimingInfo(
    duration: CMTimeMake(value: 1, timescale: 30),
    presentationTimeStamp: CMTimeMake(value: 0, timescale: 90000),
    decodeTimeStamp: .invalid
  )
  // Pass false for dataReady to create a not-ready buffer
  let sampleStatus = CMSampleBufferCreate(
    allocator: nil,
    dataBuffer: blockBuf,
    dataReady: false,
    makeDataReadyCallback: nil,
    refcon: nil,
    formatDescription: formatDesc,
    sampleCount: 1,
    sampleTimingEntryCount: 1,
    sampleTimingArray: &timing,
    sampleSizeEntryCount: 1,
    sampleSizeArray: &sampleSize,
    sampleBufferOut: &sampleBuf
  )
  assert(sampleStatus == noErr, "Failed to create sample buffer: \(sampleStatus)")

  return sampleBuf!
}

// MARK: - Tests

final class FBVideoStreamTests: XCTestCase {

  // MARK: H264 Annex-B Writer

  func testH264AnnexBKeyframeDetectionWithModernAttachments() {
    let sampleBuffer = CreateH264SampleBuffer(isKeyFrame: true)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, &error)
    XCTAssertTrue(result)
    XCTAssertNil(error)

    let output = consumer.data()

    let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
    let spsData = Data(sps)
    let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]
    let ppsData = Data(pps)

    // Keyframe IS detected: output contains SPS+PPS before NAL data.
    // Expected: [start_code][SPS][start_code][PPS][start_code][NAL]
    let spsRange = (output as NSData).range(of: spsData, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(spsRange.location, NSNotFound, "SPS should be present for keyframe")
    let ppsRange = (output as NSData).range(of: ppsData, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(ppsRange.location, NSNotFound, "PPS should be present for keyframe")

    // SPS should come before PPS
    XCTAssertTrue(spsRange.location < ppsRange.location)

    // Verify output starts with start code
    let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    let startCodeData = Data(startCode)
    let firstFourBytes = output.subdata(in: 0..<4)
    XCTAssertEqual(firstFourBytes, startCodeData)
  }

  func testH264AnnexBNonKeyframeEmitsNoParameterSets() {
    let sampleBuffer = CreateH264SampleBuffer(isKeyFrame: false)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, &error)
    XCTAssertTrue(result)
    XCTAssertNil(error)

    let output = consumer.data()

    // SPS bytes
    let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
    let spsData = Data(sps)

    // Non-keyframe should never contain SPS/PPS
    let spsRange = (output as NSData).range(of: spsData, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertEqual(spsRange.location, NSNotFound, "SPS should not be present for non-keyframe")

    // Should still contain NAL data with start code
    let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    let startCodeData = Data(startCode)
    XCTAssertTrue(output.count > 0)
    let firstFourBytes = output.subdata(in: 0..<4)
    XCTAssertEqual(firstFourBytes, startCodeData)
  }

  func testH264AnnexBAVCCToAnnexBConversion() {
    let sampleBuffer = CreateH264SampleBuffer(isKeyFrame: false)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, &error)
    XCTAssertTrue(result)
    XCTAssertNil(error)

    let output = consumer.data()

    // Expected: [00 00 00 01][65 88 80 40 00] (start code + NAL data, no AVCC length prefix)
    let expected: [UInt8] = [
      0x00, 0x00, 0x00, 0x01, // Annex-B start code
      0x65, 0x88, 0x80, 0x40, 0x00, // NAL unit data
    ]
    let expectedData = Data(expected)
    XCTAssertEqual(output, expectedData)
  }

  func testH264AnnexBNotReadyBufferReturnsError() {
    let sampleBuffer = CreateNotReadySampleBuffer()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, &error)
    XCTAssertFalse(result)
    XCTAssertNotNil(error)
    XCTAssertTrue(error!.localizedDescription.contains("Sample Buffer is not ready"))
    XCTAssertEqual(consumer.data().count, 0, "No data should be written for not-ready buffer")
  }

  // MARK: Minicap Header

  func testWriteMinicapHeader() {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteMinicapHeaderToStream(1920, 1080, consumer, logger, &error)
    XCTAssertTrue(result)
    XCTAssertNil(error)

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

  // MARK: Buffer Limit

  func testCheckConsumerBufferLimitAllowsWhenNotOverflown() {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()

    // FBAccumulatingBuffer does not conform to FBDataConsumerAsync,
    // so checkConsumerBufferLimit always returns YES.
    XCTAssertTrue(checkConsumerBufferLimit(consumer, logger))
  }

  func testCheckConsumerBufferLimitDropsWhenOverflown() {
    let consumer = FBOverflownConsumerDouble()
    let logger = FBControlCoreLoggerDouble()

    // With unprocessedDataCount = 0, should allow
    consumer.setUnprocessedDataCount(0)
    XCTAssertTrue(checkConsumerBufferLimit(consumer, logger))

    // MaxAllowedUnprocessedDataCounts is 2; > 2 triggers drop
    consumer.setUnprocessedDataCount(3)
    XCTAssertFalse(checkConsumerBufferLimit(consumer, logger))
  }

  // MARK: MPEG-TS CRC32

  func testMPEGTSCRC32KnownVector() {
    // MPEG-2 CRC32 of "123456789" is a well-known test vector
    let data: [UInt8] = [UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "3"), UInt8(ascii: "4"), UInt8(ascii: "5"), UInt8(ascii: "6"), UInt8(ascii: "7"), UInt8(ascii: "8"), UInt8(ascii: "9")]
    let crc = FBMPEGTS_CRC32(data, data.count)
    XCTAssertEqual(crc, 0x0376E6E7)
  }

  func testMPEGTSCRC32EmptyInput() {
    let emptyData: [UInt8] = []
    let crc = emptyData.withUnsafeBufferPointer { ptr in
      FBMPEGTS_CRC32(ptr.baseAddress!, 0)
    }
    XCTAssertEqual(crc, 0xFFFFFFFF)
  }

  // MARK: MPEG-TS PAT/PMT Structure

  func testPATPacketStructure() {
    var counter: UInt8 = 0
    let pat = FBMPEGTSCreatePATPacket(&counter)

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

    // Continuity counter incremented
    XCTAssertEqual(counter, 1)
  }

  func testPMTPacketStructureHEVC() {
    var counter: UInt8 = 0
    let pmt = FBMPEGTSCreatePMTPacket(&counter, 0x24)

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

    // Continuity counter incremented
    XCTAssertEqual(counter, 1)
  }

  func testPATContinuityCounterIncrements() {
    var counter: UInt8 = 0
    _ = FBMPEGTSCreatePATPacket(&counter)
    XCTAssertEqual(counter, 1)
    _ = FBMPEGTSCreatePATPacket(&counter)
    XCTAssertEqual(counter, 2)
  }

  func testPMTPacketStructureH264() {
    var counter: UInt8 = 0
    let pmt = FBMPEGTSCreatePMTPacket(&counter, 0x1B)

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

    // Stream entry: stream_type = 0x1B (H264) at section offset 12
    let section = Array(bytes[5...])
    XCTAssertEqual(section[12], 0x1B)

    // Elementary PID = 0x0101 at section offset 13-14
    let elementaryPid = UInt16(section[13] & 0x1F) << 8 | UInt16(section[14])
    XCTAssertEqual(elementaryPid, 0x0101)

    // Continuity counter incremented
    XCTAssertEqual(counter, 1)
  }

  // MARK: MPEG-TS Packetization

  func testTSPacketizationSinglePacket() {
    // Small PES payload that fits in one TS packet (< 184 bytes)
    var pesBytes = [UInt8](repeating: 0xAB, count: 100)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = FBMPEGTSPacketizePES(pesData, false, 0x24, 90000, &videoCC, &patCC, &pmtCC)

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
    let output = FBMPEGTSPacketizePES(pesData, false, 0x24, 90000, &videoCC, &patCC, &pmtCC)

    // Should produce 2 TS packets (188 * 2 = 376)
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
    let output = FBMPEGTSPacketizePES(pesData, true, 0x24, 90000, &videoCC, &patCC, &pmtCC)

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
    let output = FBMPEGTSPacketizePES(pesData, false, 0x24, 90000, &videoCC, &patCC, &pmtCC)

    // Non-keyframe: just 1 video packet
    XCTAssertEqual(output.count, 188)

    let bytes = Array(output)

    // First (and only) packet is video (PID = 0x0101), not PAT/PMT
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid, 0x0101)

    // PAT and PMT counters should not have been incremented
    XCTAssertEqual(patCC, 0)
    XCTAssertEqual(pmtCC, 0)
  }

  func testTSPacketizationKeyframeUsesH264StreamType() {
    var pesBytes = [UInt8](repeating: 0xEF, count: 50)
    let pesData = Data(bytes: &pesBytes, count: pesBytes.count)

    var videoCC: UInt8 = 0
    var patCC: UInt8 = 0
    var pmtCC: UInt8 = 0
    let output = FBMPEGTSPacketizePES(pesData, true, 0x1B, 90000, &videoCC, &patCC, &pmtCC)

    // Keyframe: PAT + PMT + 1 video packet = 3 * 188 = 564
    XCTAssertEqual(output.count, 188 * 3)

    let bytes = Array(output)

    // Second packet is PMT (PID = 0x0100)
    XCTAssertEqual(bytes[188], 0x47)

    // Verify PMT contains H264 stream type (0x1B) in the stream entry
    let pmtSection = Array(bytes[(188 + 5)...])
    XCTAssertEqual(pmtSection[12], 0x1B)
  }

  // MARK: MPEG-TS PMT with Metadata

  func testPMTWithMetadataStreamContainsTwoEntries() {
    var counter: UInt8 = 0
    let pmt = FBMPEGTSCreatePMTPacketWithMetadata(&counter, 0x24, true)

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
    XCTAssertEqual(metaPid, FBMPEGTSMetadataPID)
  }

  func testPMTWithoutMetadataStreamUnchanged() {
    var counter1: UInt8 = 0
    var counter2: UInt8 = 0
    let pmtWithout = FBMPEGTSCreatePMTPacketWithMetadata(&counter1, 0x24, false)
    let pmtOriginal = FBMPEGTSCreatePMTPacket(&counter2, 0x24)

    XCTAssertEqual(pmtWithout, pmtOriginal)
  }

  // MARK: MPEG-TS Timed Metadata Packets

  func testTimedMetadataPacketStructure() {
    var counter: UInt8 = 0
    let output = FBMPEGTSCreateTimedMetadataPackets("Chapter 1", 90000, &counter)

    XCTAssertGreaterThan(output.count, 0)
    XCTAssertEqual(output.count % 188, 0)

    let bytes = Array(output)

    // Sync byte
    XCTAssertEqual(bytes[0], 0x47)

    // payload_unit_start = 1
    XCTAssertTrue((bytes[1] & 0x40) != 0)

    // PID = MetadataPID (0x0102)
    let pid = UInt16(bytes[1] & 0x1F) << 8 | UInt16(bytes[2])
    XCTAssertEqual(pid, FBMPEGTSMetadataPID)

    // Continuity counter incremented
    XCTAssertEqual(counter, 1)

    // Find PES start code with private_stream_1 (0xBD)
    let pesStartCode = Data([0x00, 0x00, 0x01, 0xBD])
    let pesRange = (output as NSData).range(of: pesStartCode, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(pesRange.location, NSNotFound, "PES start code with private_stream_1 should be present")

    // Find ID3 header
    let id3Header = Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3")])
    let id3Range = (output as NSData).range(of: id3Header, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(id3Range.location, NSNotFound, "ID3 header should be present")

    // Find TXXX frame
    let txxxFrame = Data([UInt8(ascii: "T"), UInt8(ascii: "X"), UInt8(ascii: "X"), UInt8(ascii: "X")])
    let txxxRange = (output as NSData).range(of: txxxFrame, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(txxxRange.location, NSNotFound, "TXXX frame should be present")

    // Find the chapter text
    let chapterText = "Chapter 1".data(using: .utf8)!
    let textRange = (output as NSData).range(of: chapterText, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(textRange.location, NSNotFound, "Chapter text should be present in output")
  }

  func testTimedMetadataShortTextFitsInOnePacket() {
    var counter: UInt8 = 0
    let output = FBMPEGTSCreateTimedMetadataPackets("Hi", 0, &counter)
    XCTAssertEqual(output.count, 188)
  }

  func testTimedMetadataLongTextSpansMultiplePackets() {
    var longText = ""
    for _ in 0..<50 {
      longText.append("ABCDEFGHIJ")
    }
    var counter: UInt8 = 0
    let output = FBMPEGTSCreateTimedMetadataPackets(longText, 45000, &counter)
    XCTAssertGreaterThan(output.count, 188)
    XCTAssertEqual(output.count % 188, 0)

    let bytes = Array(output)
    let numPackets = output.count / 188
    for i in 0..<numPackets {
      XCTAssertEqual(bytes[i * 188], 0x47, "Packet \(i) should have sync byte")
      let pktPid = UInt16(bytes[i * 188 + 1] & 0x1F) << 8 | UInt16(bytes[i * 188 + 2])
      XCTAssertEqual(pktPid, FBMPEGTSMetadataPID, "Packet \(i) should have metadata PID")
    }

    XCTAssertTrue((bytes[1] & 0x40) != 0, "First packet should have payload_unit_start")
    if numPackets > 1 {
      XCTAssertFalse((bytes[189] & 0x40) != 0, "Second packet should not have payload_unit_start")
    }
  }

  // MARK: fMP4 Writer

  func testFMP4InitSegmentEmittedOnFirstKeyframe() {
    let sampleBuffer = CreateH264SampleBuffer(isKeyFrame: true)
    let ctx = FBFMP4MuxerContext(hevc: false)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteH264FrameToFMP4Stream(sampleBuffer, ctx, consumer, logger, &error)
    XCTAssertTrue(result)
    XCTAssertNil(error)
    XCTAssertTrue(ctx.initWritten)

    let output = consumer.data()
    XCTAssertGreaterThan(output.count, 16)

    let bytes = Array(output)

    // First box should be ftyp: [4-byte size]["ftyp"]
    XCTAssertEqual(bytes[4], UInt8(ascii: "f"))
    XCTAssertEqual(bytes[5], UInt8(ascii: "t"))
    XCTAssertEqual(bytes[6], UInt8(ascii: "y"))
    XCTAssertEqual(bytes[7], UInt8(ascii: "p"))

    // Read ftyp box size and find moov after it
    var ftypSize: UInt32 = 0
    withUnsafeMutableBytes(of: &ftypSize) { ptr in
      ptr.copyBytes(from: bytes[0..<4])
    }
    ftypSize = UInt32(bigEndian: ftypSize)
    XCTAssertGreaterThan(output.count, Int(ftypSize) + 8)
    XCTAssertEqual(bytes[Int(ftypSize) + 4], UInt8(ascii: "m"))
    XCTAssertEqual(bytes[Int(ftypSize) + 5], UInt8(ascii: "o"))
    XCTAssertEqual(bytes[Int(ftypSize) + 6], UInt8(ascii: "o"))
    XCTAssertEqual(bytes[Int(ftypSize) + 7], UInt8(ascii: "v"))
  }

  func testFMP4NonKeyframeBeforeFirstKeyframeDropped() {
    let nonKeyframe = CreateH264SampleBuffer(isKeyFrame: false)
    let ctx = FBFMP4MuxerContext(hevc: false)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteH264FrameToFMP4Stream(nonKeyframe, ctx, consumer, logger, &error)
    XCTAssertTrue(result)
    XCTAssertNil(error)
    XCTAssertFalse(ctx.initWritten)
    XCTAssertEqual(consumer.data().count, 0, "No data should be written before first keyframe")
  }

  func testFMP4FragmentContainsMoofAndMdat() {
    let ctx = FBFMP4MuxerContext(hevc: false)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()

    let keyframe = CreateH264SampleBuffer(isKeyFrame: true)
    _ = WriteH264FrameToFMP4Stream(keyframe, ctx, consumer, logger, nil)

    let output = consumer.data()
    let moofType = Data("moof".utf8)
    let mdatType = Data("mdat".utf8)

    let moofRange = (output as NSData).range(of: moofType, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(moofRange.location, NSNotFound, "Output should contain moof box")

    let mdatRange = (output as NSData).range(of: mdatType, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(mdatRange.location, NSNotFound, "Output should contain mdat box")

    XCTAssertTrue(moofRange.location < mdatRange.location)
    XCTAssertEqual(ctx.sequenceNumber, 1)
  }

  func testFMP4EmsgBoxStructure() {
    let ctx = FBFMP4MuxerContext(hevc: false)
    ctx.lastPts90k = 90000
    let consumer = FBDataBuffer.accumulatingBuffer()

    FBFMP4WriteEmsgBox(ctx, "Chapter 1", consumer)

    let output = consumer.data()
    XCTAssertGreaterThan(output.count, 12)

    let bytes = Array(output)

    // Box type should be "emsg"
    XCTAssertEqual(bytes[4], UInt8(ascii: "e"))
    XCTAssertEqual(bytes[5], UInt8(ascii: "m"))
    XCTAssertEqual(bytes[6], UInt8(ascii: "s"))
    XCTAssertEqual(bytes[7], UInt8(ascii: "g"))

    var boxSize: UInt32 = 0
    withUnsafeMutableBytes(of: &boxSize) { ptr in
      ptr.copyBytes(from: bytes[0..<4])
    }
    boxSize = UInt32(bigEndian: boxSize)
    XCTAssertEqual(boxSize, UInt32(output.count))

    let chapterText = "Chapter 1".data(using: .utf8)!
    let textRange = (output as NSData).range(of: chapterText, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(textRange.location, NSNotFound, "Chapter text should be present in emsg box")
  }

  func testFMP4NotReadyBufferReturnsError() {
    let sampleBuffer = CreateNotReadySampleBuffer()
    let ctx = FBFMP4MuxerContext(hevc: false)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteH264FrameToFMP4Stream(sampleBuffer, ctx, consumer, logger, &error)
    XCTAssertFalse(result)
    XCTAssertNotNil(error)
    XCTAssertTrue(error!.localizedDescription.contains("Sample Buffer is not ready"))
    XCTAssertEqual(consumer.data().count, 0)
  }

  func testFMP4NilContextReturnsError() {
    let sampleBuffer = CreateH264SampleBuffer(isKeyFrame: true)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = FBControlCoreLoggerDouble()
    var error: NSError?

    let result = WriteH264FrameToFMP4Stream(sampleBuffer, nil, consumer, logger, &error)
    XCTAssertFalse(result)
    XCTAssertNotNil(error)
  }
}
