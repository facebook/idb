/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBControlCore
import XCTest

/// fMP4 box construction (`FMP4`) and the frame writer built on it.
final class FMP4FrameWriterTests: XCTestCase {

  // MARK: - fMP4 Writer

  func testFMP4InitSegmentEmittedOnFirstKeyframe() {
    let sampleBuffer = makeH264SampleBuffer(isKeyFrame: true)
    let writer = FMP4FrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    XCTAssertNoThrow(try writer.write(sampleBuffer, to: consumer, logger: logger))
    XCTAssertTrue(writer.initWritten)

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
    let nonKeyframe = makeH264SampleBuffer(isKeyFrame: false)
    let writer = FMP4FrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    XCTAssertNoThrow(try writer.write(nonKeyframe, to: consumer, logger: logger))
    XCTAssertFalse(writer.initWritten)
    XCTAssertEqual(consumer.data().count, 0, "No data should be written before first keyframe")
  }

  func testFMP4FragmentContainsMoofAndMdat() {
    let writer = FMP4FrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    let keyframe = makeH264SampleBuffer(isKeyFrame: true)
    XCTAssertNoThrow(try writer.write(keyframe, to: consumer, logger: logger))

    let output = consumer.data()
    let moofType = Data("moof".utf8)
    let mdatType = Data("mdat".utf8)

    let moofRange = (output as NSData).range(of: moofType, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(moofRange.location, NSNotFound, "Output should contain moof box")

    let mdatRange = (output as NSData).range(of: mdatType, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(mdatRange.location, NSNotFound, "Output should contain mdat box")

    XCTAssertTrue(moofRange.location < mdatRange.location)
    XCTAssertEqual(writer.sequenceNumber, 1)
  }

  func testFMP4FragmentTrunBoxSize() {
    let writer = FMP4FrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    XCTAssertNoThrow(try writer.write(makeH264SampleBuffer(isKeyFrame: true), to: consumer, logger: logger))

    let output = consumer.data()
    let trunRange = (output as NSData).range(of: Data("trun".utf8), options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(trunRange.location, NSNotFound, "Fragment should contain a trun box")
    let trunSize = output.withUnsafeBytes { ptr -> UInt32 in
      UInt32(bigEndian: ptr.loadUnaligned(fromByteOffset: trunRange.location - 4, as: UInt32.self))
    }
    let trafRange = (output as NSData).range(of: Data("traf".utf8), options: [], in: NSRange(location: 0, length: output.count))
    let trafSize = output.withUnsafeBytes { ptr -> UInt32 in
      UInt32(bigEndian: ptr.loadUnaligned(fromByteOffset: trafRange.location - 4, as: UInt32.self))
    }
    // trun is the last child of traf, so its size is the bytes from its own header to traf's end:
    // header(12) + sample_count(4) + data_offset(4) + one sample entry (duration, size, flags = 12).
    let expectedTrunSize = UInt32(trafRange.location - 4) + trafSize - UInt32(trunRange.location - 4)
    XCTAssertEqual(expectedTrunSize, 32)
    // A size of 0 would mean "box extends to end of file" (ISO 14496-12 §4.2), which Chrome's MSE
    // demuxer refuses ("ISO BMFF boxes that run to EOS are not supported").
    XCTAssertEqual(trunSize, expectedTrunSize)
  }

  func testFMP4EveryBoxHasPinnedBoundary() throws {
    let writer = FMP4FrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    try writer.write(makeH264SampleBuffer(isKeyFrame: true), to: consumer, logger: logger)

    let output = consumer.data()
    let h264Golden = try XCTUnwrap(
      Data(
        base64Encoded: """
          AAAAHGZ0eXBpc29tAAACAGlzb21pc282bXA0MQAAAmVtb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAV+QAAAAAAABAAABAAAA
          AAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC
          AAAByXRyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAA
          AAEAAAAAAAAAAAAAAAAAAEAAAAAAgAAAAGAAAAAAAWVtZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAAV+QAAAAAFXEAAAAAAAt
          aGRscgAAAAAAAAAAdmlkZQAAAAAAAAAAAAAAAFZpZGVvSGFuZGxlcgAAAAEQbWluZgAAABR2bWhkAAAAAQAAAAAAAAAAAAAA
          JGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAA0HN0YmwAAACEc3RzZAAAAAAAAAABAAAAdGF2YzEAAAAAAAAA
          AQAAAAAAAAAAAAAAAAAAAAAAgABgAEgAAABIAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAY//8A
          AAAeYXZjQwFCAAr/4QAHZ0IACvhBogEABGjOOIAAAAAQc3R0cwAAAAAAAAAAAAAAEHN0c2MAAAAAAAAAAAAAABRzdHN6AAAA
          AAAAAAAAAAAAAAAAEHN0Y28AAAAAAAAAAAAAAChtdmV4AAAAIHRyZXgAAAAAAAAAAQAAAAEAAAAAAAAAAAAAAAAAAABkbW9v
          ZgAAABBtZmhkAAAAAAAAAAEAAABMdHJhZgAAABB0ZmhkAAIAAAAAAAEAAAAUdGZkdAEAAAAAAAAAAAAAAAAAACB0cnVuAAAH
          AQAAAAEAAABsAAALuAAAAAkCAAAAAAAAEW1kYXQAAAAFZYiAQAA=
          """,
        options: .ignoreUnknownCharacters
      )
    )
    XCTAssertEqual(output, h264Golden)
    XCTAssertEqual(
      try fmp4BoxSignatures(output, in: 0..<output.count),
      [
        "ftyp:28",
        "moov:613",
        "moov/mvhd:108",
        "moov/trak:457",
        "moov/trak/tkhd:92",
        "moov/trak/mdia:357",
        "moov/trak/mdia/mdhd:32",
        "moov/trak/mdia/hdlr:45",
        "moov/trak/mdia/minf:272",
        "moov/trak/mdia/minf/vmhd:20",
        "moov/trak/mdia/minf/dinf:36",
        "moov/trak/mdia/minf/dinf/dref:28",
        "moov/trak/mdia/minf/dinf/dref/url :12",
        "moov/trak/mdia/minf/stbl:208",
        "moov/trak/mdia/minf/stbl/stsd:132",
        "moov/trak/mdia/minf/stbl/stsd/avc1:116",
        "moov/trak/mdia/minf/stbl/stsd/avc1/avcC:30",
        "moov/trak/mdia/minf/stbl/stts:16",
        "moov/trak/mdia/minf/stbl/stsc:16",
        "moov/trak/mdia/minf/stbl/stsz:20",
        "moov/trak/mdia/minf/stbl/stco:16",
        "moov/mvex:40",
        "moov/mvex/trex:32",
        "moof:100",
        "moof/mfhd:16",
        "moof/traf:76",
        "moof/traf/tfhd:16",
        "moof/traf/tfdt:20",
        "moof/traf/trun:32",
        "mdat:17",
      ]
    )

    let hevcWriter = FMP4FrameWriter(codec: .hevc)
    let hevcConsumer = FBDataBuffer.accumulatingBuffer()
    let hevcSampleBuffer = try XCTUnwrap(makeHEVCSampleBuffer(isKeyFrame: true))
    try hevcWriter.write(hevcSampleBuffer, to: hevcConsumer, logger: logger)
    let hevcGolden = try XCTUnwrap(
      Data(
        base64Encoded: """
          AAAAHGZ0eXBpc29tAAACAGlzb21pc282aHZjMQAAAr5tb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAV+QAAAAAAABAAABAAAA
          AAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC
          AAACInRyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAA
          AAEAAAAAAAAAAAAAAAAAAEAAAAAHgAAABDgAAAAAAb5tZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAAV+QAAAAAFXEAAAAAAAt
          aGRscgAAAAAAAAAAdmlkZQAAAAAAAAAAAAAAAFZpZGVvSGFuZGxlcgAAAAFpbWluZgAAABR2bWhkAAAAAQAAAAAAAAAAAAAA
          JGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAABKXN0YmwAAADdc3RzZAAAAAAAAAABAAAAzWh2YzEAAAAAAAAA
          AQAAAAAAAAAAAAAAAAAAAAAHgAQ4AEgAAABIAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAY//8A
          AAB3aHZjQwEBYAAAAJAAAAAAAHjwAPz9+PgAAA8DoAABABhAAQwB//8BYAAAAwCQAAADAAADAHiZmAmhAAEAKkIBAQFgAAAD
          AJAAAAMAAAMAeKADwIAQ5ZZWaSTK4BAAAAMAEAAAAwHggKIAAQAHRAHBcrRiQAAAABBzdHRzAAAAAAAAAAAAAAAQc3RzYwAA
          AAAAAAAAAAAAFHN0c3oAAAAAAAAAAAAAAAAAAAAQc3RjbwAAAAAAAAAAAAAAKG12ZXgAAAAgdHJleAAAAAAAAAABAAAAAQAA
          AAAAAAAAAAAAAAAAAGRtb29mAAAAEG1maGQAAAAAAAAAAQAAAEx0cmFmAAAAEHRmaGQAAgAAAAAAAQAAABR0ZmR0AQAAAAAA
          AAAAAAAAAAAAIHRydW4AAAcBAAAAAQAAAGwAAAu4AAAACgIAAAAAAAASbWRhdAAAAAYmAa8IQAA=
          """,
        options: .ignoreUnknownCharacters
      )
    )
    XCTAssertEqual(hevcConsumer.data(), hevcGolden)

    let metadataConsumer = FBDataBuffer.accumulatingBuffer()
    writer.writeTimedMetadata("Chapter 1", to: metadataConsumer)
    let metadata = metadataConsumer.data()
    let metadataGolden = try XCTUnwrap(
      Data(
        base64Encoded: "AAAAPWVtc2cBAAAAAAFfkAAAAAAAAAAAAAAAAAAAAAB1cm46c2ltZTJlOmNoYXB0ZXIAAENoYXB0ZXIgMQ=="
      )
    )
    XCTAssertEqual(metadata, metadataGolden)
    XCTAssertEqual(try fmp4BoxSignatures(metadata, in: 0..<metadata.count), ["emsg:61"])
  }

  func testFMP4FragmentBaseDecodeTimeFollowsPresentationTime() {
    let writer = FMP4FrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    // A source that missed cadence: each sample declares 1/30 s but the frames are 100 ms apart.
    let ptsList: [Int64] = [0, 9000, 18000, 27000]
    for (index, pts) in ptsList.enumerated() {
      XCTAssertNoThrow(try writer.write(makeH264SampleBuffer(isKeyFrame: index == 0, pts90k: pts), to: consumer, logger: logger))
    }

    let output = consumer.data()
    var tfdts: [UInt64] = []
    var searchFrom = 0
    while true {
      let range = (output as NSData).range(of: Data("tfdt".utf8), options: [], in: NSRange(location: searchFrom, length: output.count - searchFrom))
      if range.location == NSNotFound { break }
      // tfdt v1: 4-byte type, 4-byte version/flags, 8-byte baseMediaDecodeTime
      tfdts.append(output.withUnsafeBytes { ptr in UInt64(bigEndian: ptr.loadUnaligned(fromByteOffset: range.location + 8, as: UInt64.self)) })
      searchFrom = range.location + 4
    }
    XCTAssertEqual(tfdts.count, ptsList.count)
    // baseMediaDecodeTime follows the sample's presentation time (relative to the first sample), so a
    // source that misses its declared cadence still carries a media clock that tracks real time.
    XCTAssertEqual(tfdts, [0, 9000, 18000, 27000])
  }

  func testFMP4EmsgBoxStructure() {
    let writer = FMP4FrameWriter(codec: .h264)
    writer.lastPts90k = 90000
    let consumer = FBDataBuffer.accumulatingBuffer()

    writer.writeTimedMetadata("Chapter 1", to: consumer)

    let output = consumer.data()
    XCTAssertGreaterThan(output.count, 12)

    let bytes = Array(output)

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

  func testFMP4NotReadyBufferReturnsError() throws {
    let sampleBuffer = makeNotReadySampleBuffer()
    let writer = FMP4FrameWriter(codec: .h264)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    XCTAssertThrowsError(try writer.write(sampleBuffer, to: consumer, logger: logger)) { error in
      XCTAssertTrue(error.localizedDescription.contains("Sample Buffer is not ready"))
    }
    XCTAssertEqual(consumer.data().count, 0)
  }

  func testHEVCFMP4InitSegmentUsesHVC1AndHVCC() throws {
    let sampleBuffer = try XCTUnwrap(makeHEVCSampleBuffer(isKeyFrame: true))
    let writer = FMP4FrameWriter(codec: .hevc)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()

    XCTAssertNoThrow(try writer.write(sampleBuffer, to: consumer, logger: logger))
    XCTAssertTrue(writer.initWritten)

    let output = consumer.data()
    XCTAssertEqual(output.subdata(in: 4..<8), Data("ftyp".utf8))
    let hvc1 = (output as NSData).range(of: Data("hvc1".utf8), options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(hvc1.location, NSNotFound, "fMP4 should declare the hvc1 brand for HEVC")
    let hvcC = (output as NSData).range(of: Data("hvcC".utf8), options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(hvcC.location, NSNotFound, "moov should contain an hvcC config box for HEVC")
  }

  func testFMP4FirstKeyframeCostsOneWrite() throws {
    let counting = CountingConsumer()
    try FMP4FrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: true), to: counting.consumer, logger: ControlCoreLoggerDouble())
    XCTAssertEqual(counting.writes, 1)
  }

  // MARK: - fMP4 Format Changes

  func testFMP4KeyframeWithANewFormatDescriptionReemitsTheInitSegment() throws {
    let counting = CountingConsumer()
    let writer = FMP4FrameWriter(codec: .h264)
    let logger = ControlCoreLoggerDouble()
    try writer.write(makeH264SampleBuffer(isKeyFrame: true), to: counting.consumer, logger: logger)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 3000, sps: alternateTestSPS), to: counting.consumer, logger: logger)

    // Walk the box structure rather than scanning for the bytes "ftyp", which could occur inside a
    // payload.
    let initSegments = try fmp4BoxSignatures(counting.bytes, in: 0..<counting.bytes.count).filter { $0.hasPrefix("ftyp:") }.count
    XCTAssertEqual(initSegments, 2)
  }

  func testFMP4KeyframeWithTheSameFormatDescriptionDoesNotReemitTheInitSegment() throws {
    let counting = CountingConsumer()
    let writer = FMP4FrameWriter(codec: .h264)
    let logger = ControlCoreLoggerDouble()
    try writer.write(makeH264SampleBuffer(isKeyFrame: true), to: counting.consumer, logger: logger)
    let afterFirst = counting.bytes.count
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 3000), to: counting.consumer, logger: logger)

    let second = counting.bytes.subdata(in: afterFirst..<counting.bytes.count)
    XCTAssertEqual((second as NSData).range(of: Data("ftyp".utf8), options: [], in: NSRange(location: 0, length: second.count)).location, NSNotFound)
  }
}
