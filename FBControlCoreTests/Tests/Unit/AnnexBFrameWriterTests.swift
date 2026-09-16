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
