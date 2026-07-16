/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import FBControlCore
@testable import FBSimulatorControl
import VideoToolbox
import XCTest

/// Creates an H264 CMSampleBuffer suitable for testing.
/// The buffer is marked as data-ready.
func createH264SampleBuffer() -> CMSampleBuffer {
  let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
  let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]

  var formatDesc: CMFormatDescription?
  let status1 = sps.withUnsafeBufferPointer { spsPtr in
    pps.withUnsafeBufferPointer { ppsPtr in
      var paramSets: [UnsafePointer<UInt8>] = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
      var paramSizes = [spsPtr.count, ppsPtr.count]
      return CMVideoFormatDescriptionCreateFromH264ParameterSets(
        allocator: nil,
        parameterSetCount: 2,
        parameterSetPointers: &paramSets,
        parameterSetSizes: &paramSizes,
        nalUnitHeaderLength: 4,
        formatDescriptionOut: &formatDesc
      )
    }
  }
  precondition(status1 == noErr, "Failed to create H264 format description: \(status1)")

  var avccData: [UInt8] = [
    0x00, 0x00, 0x00, 0x05,
    0x65, 0x88, 0x80, 0x40, 0x00,
  ]

  var blockBuf: CMBlockBuffer?
  let status2 = avccData.withUnsafeMutableBufferPointer { ptr in
    CMBlockBufferCreateWithMemoryBlock(
      allocator: nil,
      memoryBlock: ptr.baseAddress,
      blockLength: ptr.count,
      blockAllocator: kCFAllocatorNull,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: ptr.count,
      flags: 0,
      blockBufferOut: &blockBuf
    )
  }
  precondition(status2 == noErr, "Failed to create block buffer: \(status2)")

  var sampleBuf: CMSampleBuffer?
  var sampleSize = avccData.count
  var timing = CMSampleTimingInfo(
    duration: CMTimeMake(value: 1, timescale: 30),
    presentationTimeStamp: CMTimeMake(value: 0, timescale: 90000),
    decodeTimeStamp: .invalid
  )
  let status3 = CMSampleBufferCreate(
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
  precondition(status3 == noErr, "Failed to create sample buffer: \(status3)")

  return sampleBuf!
}

/// Creates an H264 CMSampleBuffer that is NOT data-ready.
/// Used to simulate encoder warmup / starvation scenarios.
func createNotReadySampleBuffer() -> CMSampleBuffer {
  let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
  let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]

  var formatDesc: CMFormatDescription?
  let status1 = sps.withUnsafeBufferPointer { spsPtr in
    pps.withUnsafeBufferPointer { ppsPtr in
      var paramSets: [UnsafePointer<UInt8>] = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
      var paramSizes = [spsPtr.count, ppsPtr.count]
      return CMVideoFormatDescriptionCreateFromH264ParameterSets(
        allocator: nil,
        parameterSetCount: 2,
        parameterSetPointers: &paramSets,
        parameterSetSizes: &paramSizes,
        nalUnitHeaderLength: 4,
        formatDescriptionOut: &formatDesc
      )
    }
  }
  precondition(status1 == noErr, "Failed to create H264 format description: \(status1)")

  var avccData: [UInt8] = [
    0x00, 0x00, 0x00, 0x05,
    0x65, 0x88, 0x80, 0x40, 0x00,
  ]

  var blockBuf: CMBlockBuffer?
  let status2 = avccData.withUnsafeMutableBufferPointer { ptr in
    CMBlockBufferCreateWithMemoryBlock(
      allocator: nil,
      memoryBlock: ptr.baseAddress,
      blockLength: ptr.count,
      blockAllocator: kCFAllocatorNull,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: ptr.count,
      flags: 0,
      blockBufferOut: &blockBuf
    )
  }
  precondition(status2 == noErr, "Failed to create block buffer: \(status2)")

  var sampleBuf: CMSampleBuffer?
  var sampleSize = avccData.count
  var timing = CMSampleTimingInfo(
    duration: CMTimeMake(value: 1, timescale: 30),
    presentationTimeStamp: CMTimeMake(value: 0, timescale: 90000),
    decodeTimeStamp: .invalid
  )
  // Pass false for dataReady to create a not-ready buffer
  let status3 = CMSampleBufferCreate(
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
  precondition(status3 == noErr, "Failed to create sample buffer: \(status3)")

  return sampleBuf!
}

/// A test double logger that captures all logged messages for assertion.
/// Re-expressed in Swift now that the pushers are Swift (the ObjC bridge double is gone).
final class FBCapturingLogger: NSObject, FBControlCoreLogger {
  let messages = NSMutableArray()

  @discardableResult
  func log(_ message: String) -> FBControlCoreLogger {
    messages.add(message)
    return self
  }

  func info() -> FBControlCoreLogger { self }
  func debug() -> FBControlCoreLogger { self }
  func error() -> FBControlCoreLogger { self }
  func withName(_ prefix: String) -> FBControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger { self }
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }
}

/// Creates a FBSimulatorVideoStreamFramePusher_VideoToolbox configured for H264/AnnexB testing.
/// Constructed directly in Swift now that the pusher is a Swift class. The pusher uses the
/// block-based encode handler at runtime, but the tests drive `handleCompressedSampleBuffer`
/// directly, so only the `.compressed` output mode is needed here.
func createTestVideoStreamPusher(_ logger: FBControlCoreLogger) -> FBSimulatorVideoStreamFramePusher_VideoToolbox {
  let format = FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB)
  let config = FBVideoStreamConfiguration(
    format: format,
    framesPerSecond: 30,
    rateControl: nil,
    scaleFactor: nil,
    keyFrameRate: 10.0)
  let consumer = FBDataBuffer.accumulatingBuffer()
  return FBSimulatorVideoStreamFramePusher_VideoToolbox(
    configuration: config,
    compressionSessionProperties: [:],
    videoCodec: kCMVideoCodecType_H264,
    consumer: consumer,
    outputMode: .compressed,
    encodedSampleConsumer: FBDataConsumerEncodedSampleConsumer(
      consumer: consumer, frameWriter: FBAnnexBFrameWriter(hevc: false)),
    logger: logger)
}
