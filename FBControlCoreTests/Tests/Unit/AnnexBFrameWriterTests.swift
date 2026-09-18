/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBControlCore
import XCTest

/// Annex-B framing: start codes, parameter sets ahead of keyframes, one write per frame.
final class AnnexBFrameWriterTests: XCTestCase {

  // MARK: - H264 Annex-B Writer

  func testH264AnnexBKeyframeDetectionWithModernAttachments() {
    let sampleBuffer = makeH264SampleBuffer(isKeyFrame: true)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = AnnexBFrameWriter(codec: .h264)

    XCTAssertNoThrow(try writer.write(sampleBuffer, to: consumer, logger: logger))

    let output = consumer.data()

    let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
    let spsData = Data(sps)
    let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]
    let ppsData = Data(pps)

    // Expected layout: [start_code][SPS][start_code][PPS][start_code][NAL]
    let spsRange = (output as NSData).range(of: spsData, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(spsRange.location, NSNotFound, "SPS should be present for keyframe")
    let ppsRange = (output as NSData).range(of: ppsData, options: [], in: NSRange(location: 0, length: output.count))
    XCTAssertNotEqual(ppsRange.location, NSNotFound, "PPS should be present for keyframe")

    XCTAssertTrue(spsRange.location < ppsRange.location)

    let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    let startCodeData = Data(startCode)
    let firstFourBytes = output.subdata(in: 0..<4)
    XCTAssertEqual(firstFourBytes, startCodeData)
  }

  func testH264AnnexBAVCCToAnnexBConversion() {
    let sampleBuffer = makeH264SampleBuffer(isKeyFrame: false)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = AnnexBFrameWriter(codec: .h264)

    XCTAssertNoThrow(try writer.write(sampleBuffer, to: consumer, logger: logger))

    let output = consumer.data()

    // The 4-byte AVCC length prefix is replaced by the start code.
    let expected: [UInt8] = [
      0x00, 0x00, 0x00, 0x01, // Annex-B start code
      0x65, 0x88, 0x80, 0x40, 0x00, // NAL unit data
    ]
    let expectedData = Data(expected)
    XCTAssertEqual(output, expectedData)
  }

  // MARK: - Malformed AVCC Lengths

  func testAnnexBLengthPrefixShorterThanItsNALOverwritesPayloadWithAStartCode() throws {
    // One eight-byte NAL whose prefix claims three bytes.
    let avcc: [UInt8] = [
      0x00, 0x00, 0x00, 0x03,
      0x65, 0x88, 0x80, 0x40, 0x00, 0x11, 0x22, 0x33,
    ]
    let consumer = FBDataBuffer.accumulatingBuffer()
    try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: false, avccBytes: avcc), to: consumer, logger: ControlCoreLoggerDouble())

    // BUG: after the three claimed bytes the walk reads `40 00 11 22` as the next length prefix and
    // overwrites those payload bytes with a start code — flipped to a thrown error in the following
    // commit.
    XCTAssertEqual([UInt8](consumer.data()), [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x80, 0x00, 0x00, 0x00, 0x01, 0x33])
  }

  func testAnnexBLengthPrefixLongerThanTheBufferIsWrittenAsIs() throws {
    // One NAL whose prefix claims 200 bytes; only five follow.
    let avcc: [UInt8] = [
      0x00, 0x00, 0x00, 0xC8,
      0x65, 0x88, 0x80, 0x40, 0x00,
    ]
    let consumer = FBDataBuffer.accumulatingBuffer()
    try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: false, avccBytes: avcc), to: consumer, logger: ControlCoreLoggerDouble())

    // BUG: the truncated sample is emitted as though well-formed — flipped to a thrown error in the
    // following commit.
    XCTAssertEqual([UInt8](consumer.data()), [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x80, 0x40, 0x00])
  }

  func testAnnexBTrailingPartialPrefixIsPassedThrough() throws {
    let avcc: [UInt8] = [
      0x00, 0x00, 0x00, 0x02, 0x65, 0x88,
      0x00, 0x00, // two bytes where a prefix should be
    ]
    let consumer = FBDataBuffer.accumulatingBuffer()
    try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: false, avccBytes: avcc), to: consumer, logger: ControlCoreLoggerDouble())

    // BUG: the two stray bytes ride out after the NAL unit — flipped to a thrown error in the
    // following commit.
    XCTAssertEqual([UInt8](consumer.data()), [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x00, 0x00])
  }

  func testAnnexBTwoWellFormedNALUnitsBothGetStartCodes() throws {
    let avcc: [UInt8] = [
      0x00, 0x00, 0x00, 0x02, 0x65, 0x88,
      0x00, 0x00, 0x00, 0x03, 0x41, 0x9a, 0x00,
    ]
    let consumer = FBDataBuffer.accumulatingBuffer()
    try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: false, avccBytes: avcc), to: consumer, logger: ControlCoreLoggerDouble())
    XCTAssertEqual([UInt8](consumer.data()), [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x00, 0x00, 0x00, 0x01, 0x41, 0x9a, 0x00])
  }

  func testH264AnnexBNotReadyBufferReturnsError() throws {
    let sampleBuffer = makeNotReadySampleBuffer()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = AnnexBFrameWriter(codec: .h264)

    XCTAssertThrowsError(try writer.write(sampleBuffer, to: consumer, logger: logger)) { error in
      XCTAssertTrue(error.localizedDescription.contains("Sample Buffer is not ready"))
    }
    XCTAssertEqual(consumer.data().count, 0, "No data should be written for not-ready buffer")
  }

  // MARK: - HEVC Writers

  func testHEVCAnnexBKeyframeEmitsParameterSets() throws {
    let sampleBuffer = try XCTUnwrap(makeHEVCSampleBuffer(isKeyFrame: true))
    let consumer = FBDataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = AnnexBFrameWriter(codec: .hevc)

    XCTAssertNoThrow(try writer.write(sampleBuffer, to: consumer, logger: logger))

    let output = consumer.data()

    for (name, set) in [("VPS", hevcVPS), ("SPS", hevcSPS), ("PPS", hevcPPS)] {
      let range = (output as NSData).range(of: Data(set), options: [], in: NSRange(location: 0, length: output.count))
      XCTAssertNotEqual(range.location, NSNotFound, "\(name) should be present for an HEVC keyframe")
    }

    XCTAssertEqual(output.subdata(in: 0..<4), Data([0x00, 0x00, 0x00, 0x01]))
  }

  // MARK: - Writes Per Frame

  func testAnnexBKeyframeCostsOneWrite() throws {
    let counting = CountingConsumer()
    try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: true), to: counting.consumer, logger: ControlCoreLoggerDouble())
    XCTAssertEqual(counting.writes, 1)
    XCTAssertEqual(counting.bytes.count, 4 + 7 + 4 + 4 + 9)
  }
}
