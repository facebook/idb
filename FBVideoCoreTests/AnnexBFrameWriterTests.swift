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

/// Annex-B framing: start codes, parameter sets ahead of keyframes, one write per frame.
@Suite
struct AnnexBFrameWriterTests {

  // MARK: - H264 Annex-B Writer

  @Test
  func h264AnnexBKeyframeDetectionWithModernAttachments() {
    let sampleBuffer = makeH264SampleBuffer(isKeyFrame: true)
    let consumer = DataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = AnnexBFrameWriter(codec: .h264)

    #expect(throws: Never.self) { try writer.write(sampleBuffer, to: consumer, logger: logger) }

    let output = consumer.data()

    let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
    let spsData = Data(sps)
    let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]
    let ppsData = Data(pps)

    // Expected layout: [start_code][SPS][start_code][PPS][start_code][NAL]
    let spsRange = (output as NSData).range(of: spsData, options: [], in: NSRange(location: 0, length: output.count))
    #expect(spsRange.location != NSNotFound, "SPS should be present for keyframe")
    let ppsRange = (output as NSData).range(of: ppsData, options: [], in: NSRange(location: 0, length: output.count))
    #expect(ppsRange.location != NSNotFound, "PPS should be present for keyframe")

    #expect(spsRange.location < ppsRange.location)

    let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    let startCodeData = Data(startCode)
    let firstFourBytes = output.subdata(in: 0..<4)
    #expect(firstFourBytes == startCodeData)
  }

  @Test
  func h264AnnexBAVCCToAnnexBConversion() {
    let sampleBuffer = makeH264SampleBuffer(isKeyFrame: false)
    let consumer = DataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = AnnexBFrameWriter(codec: .h264)

    #expect(throws: Never.self) { try writer.write(sampleBuffer, to: consumer, logger: logger) }

    let output = consumer.data()

    // The 4-byte AVCC length prefix is replaced by the start code.
    let expected: [UInt8] = [
      0x00, 0x00, 0x00, 0x01, // Annex-B start code
      0x65, 0x88, 0x80, 0x40, 0x00, // NAL unit data
    ]
    let expectedData = Data(expected)
    #expect(output == expectedData)
  }

  // MARK: - Malformed AVCC Lengths

  @Test
  func annexBLengthPrefixShorterThanItsNALIsRefused() throws {
    // One eight-byte NAL whose prefix claims three bytes: the bytes after the claimed three do not
    // form a prefix that fits, so the sample is refused rather than emitted with them rewritten.
    let avcc: [UInt8] = [
      0x00, 0x00, 0x00, 0x03,
      0x65, 0x88, 0x80, 0x40, 0x00, 0x11, 0x22, 0x33,
    ]
    let consumer = DataBuffer.accumulatingBuffer()
    let error = #expect(throws: (any Error).self) {
      try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: false, avccBytes: avcc), to: consumer, logger: ControlCoreLoggerDouble())
    }
    let isExpectedError = if case .malformedNALUnitLength(offset: 7, length: 0x4000_1122, remaining: 1)? = error as? EncodedFrameWriterError { true } else { false }
    #expect(isExpectedError, "Expected malformedNALUnitLength at the misread prefix, got \(String(describing: error))")
    #expect(consumer.data().count == 0, "Nothing reaches the consumer for a refused sample")
  }

  @Test
  func annexBLengthPrefixLongerThanTheBufferIsRefused() throws {
    // One NAL whose prefix claims 200 bytes; only five follow.
    let avcc: [UInt8] = [
      0x00, 0x00, 0x00, 0xC8,
      0x65, 0x88, 0x80, 0x40, 0x00,
    ]
    let consumer = DataBuffer.accumulatingBuffer()
    let error = #expect(throws: (any Error).self) {
      try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: false, avccBytes: avcc), to: consumer, logger: ControlCoreLoggerDouble())
    }
    let isExpectedError = if case .malformedNALUnitLength(offset: 0, length: 200, remaining: 5)? = error as? EncodedFrameWriterError { true } else { false }
    #expect(isExpectedError, "Expected malformedNALUnitLength for the oversize prefix, got \(String(describing: error))")
    #expect(consumer.data().count == 0)
  }

  @Test
  func annexBTrailingPartialPrefixIsRefused() throws {
    let avcc: [UInt8] = [
      0x00, 0x00, 0x00, 0x02, 0x65, 0x88,
      0x00, 0x00, // two bytes where a prefix should be
    ]
    let consumer = DataBuffer.accumulatingBuffer()
    #expect(throws: (any Error).self) { try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: false, avccBytes: avcc), to: consumer, logger: ControlCoreLoggerDouble()) }
    #expect(consumer.data().count == 0)
  }

  @Test
  func annexBTwoWellFormedNALUnitsBothGetStartCodes() throws {
    let avcc: [UInt8] = [
      0x00, 0x00, 0x00, 0x02, 0x65, 0x88,
      0x00, 0x00, 0x00, 0x03, 0x41, 0x9a, 0x00,
    ]
    let consumer = DataBuffer.accumulatingBuffer()
    try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: false, avccBytes: avcc), to: consumer, logger: ControlCoreLoggerDouble())
    #expect([UInt8](consumer.data()) == [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x00, 0x00, 0x00, 0x01, 0x41, 0x9a, 0x00])
  }

  @Test
  func h264AnnexBNotReadyBufferReturnsError() throws {
    let sampleBuffer = makeNotReadySampleBuffer()
    let consumer = DataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = AnnexBFrameWriter(codec: .h264)

    let error = #expect(throws: (any Error).self) { try writer.write(sampleBuffer, to: consumer, logger: logger) }
    #expect(error?.localizedDescription.contains("Sample Buffer is not ready") == true)
    #expect(consumer.data().count == 0, "No data should be written for not-ready buffer")
  }

  // MARK: - HEVC Writers

  @Test
  func hevcAnnexBKeyframeEmitsParameterSets() throws {
    let sampleBuffer = try #require(makeHEVCSampleBuffer(isKeyFrame: true))
    let consumer = DataBuffer.accumulatingBuffer()
    let logger = ControlCoreLoggerDouble()
    let writer = AnnexBFrameWriter(codec: .hevc)

    #expect(throws: Never.self) { try writer.write(sampleBuffer, to: consumer, logger: logger) }

    let output = consumer.data()

    for (name, set) in [("VPS", hevcVPS), ("SPS", hevcSPS), ("PPS", hevcPPS)] {
      let range = (output as NSData).range(of: Data(set), options: [], in: NSRange(location: 0, length: output.count))
      #expect(range.location != NSNotFound, "\(name) should be present for an HEVC keyframe")
    }

    #expect(output.subdata(in: 0..<4) == Data([0x00, 0x00, 0x00, 0x01]))
  }

  // MARK: - Writes Per Frame

  @Test
  func annexBKeyframeCostsOneWrite() throws {
    let counting = CountingConsumer()
    try AnnexBFrameWriter(codec: .h264).write(makeH264SampleBuffer(isKeyFrame: true), to: counting.consumer, logger: ControlCoreLoggerDouble())
    #expect(counting.writes == 1)
    #expect(counting.bytes.count == 4 + 7 + 4 + 4 + 9)
  }
}
