/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import CoreVideo
import FBControlCore
import Foundation

/// A test double logger that captures all logged messages for assertion.
final class CapturingLogger: NSObject, FBControlCoreLogger {
  let messages = NSMutableArray()

  @discardableResult
  func log(_ message: String) -> any FBControlCoreLogger {
    messages.add(message)
    return self
  }

  func info() -> any FBControlCoreLogger { self }
  func debug() -> any FBControlCoreLogger { self }
  func error() -> any FBControlCoreLogger { self }
  func withName(_ name: String) -> any FBControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any FBControlCoreLogger { self }
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }
}

// MARK: - CMSampleBuffer builders

/// Creates a CMBlockBuffer that owns a copy of `bytes` (no dangling reference to caller storage).
func makeOwnedBlockBuffer(_ bytes: [UInt8]) -> CMBlockBuffer {
  var blockBuffer: CMBlockBuffer?
  let status = CMBlockBufferCreateWithMemoryBlock(
    allocator: kCFAllocatorDefault,
    memoryBlock: nil,
    blockLength: bytes.count,
    blockAllocator: kCFAllocatorDefault,
    customBlockSource: nil,
    offsetToData: 0,
    dataLength: bytes.count,
    flags: kCMBlockBufferAssureMemoryNowFlag,
    blockBufferOut: &blockBuffer
  )
  precondition(status == kCMBlockBufferNoErr, "CMBlockBufferCreateWithMemoryBlock failed: \(status)")
  let block = blockBuffer!
  bytes.withUnsafeBytes { raw in
    let replaceStatus = CMBlockBufferReplaceDataBytes(
      with: raw.baseAddress!,
      blockBuffer: block,
      offsetIntoDestination: 0,
      dataLength: bytes.count
    )
    precondition(replaceStatus == kCMBlockBufferNoErr, "CMBlockBufferReplaceDataBytes failed: \(replaceStatus)")
  }
  return block
}

/// Creates a data-ready H264 keyframe (IDR) CMSampleBuffer with a valid format description.
/// The encoded slice is an AVCC (length-prefixed) NAL; the Annex-B / MPEG-TS writers convert it.
func makeH264SampleBuffer() -> CMSampleBuffer {
  let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
  let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]

  var formatDescription: CMFormatDescription?
  let formatStatus = sps.withUnsafeBufferPointer { spsPtr in
    pps.withUnsafeBufferPointer { ppsPtr in
      var paramSets: [UnsafePointer<UInt8>] = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
      var paramSizes = [spsPtr.count, ppsPtr.count]
      return CMVideoFormatDescriptionCreateFromH264ParameterSets(
        allocator: nil,
        parameterSetCount: 2,
        parameterSetPointers: &paramSets,
        parameterSetSizes: &paramSizes,
        nalUnitHeaderLength: 4,
        formatDescriptionOut: &formatDescription
      )
    }
  }
  precondition(formatStatus == noErr, "Failed to create H264 format description: \(formatStatus)")

  // 4-byte AVCC length prefix (5) + a 5-byte IDR slice NAL.
  let avccData: [UInt8] = [0x00, 0x00, 0x00, 0x05, 0x65, 0x88, 0x80, 0x40, 0x00]
  let blockBuffer = makeOwnedBlockBuffer(avccData)

  var sampleBuffer: CMSampleBuffer?
  var sampleSize = avccData.count
  var timing = CMSampleTimingInfo(
    duration: CMTimeMake(value: 1, timescale: 30),
    presentationTimeStamp: CMTimeMake(value: 0, timescale: 90000),
    decodeTimeStamp: .invalid
  )
  let sampleStatus = CMSampleBufferCreate(
    allocator: nil,
    dataBuffer: blockBuffer,
    dataReady: true,
    makeDataReadyCallback: nil,
    refcon: nil,
    formatDescription: formatDescription,
    sampleCount: 1,
    sampleTimingEntryCount: 1,
    sampleTimingArray: &timing,
    sampleSizeEntryCount: 1,
    sampleSizeArray: &sampleSize,
    sampleBufferOut: &sampleBuffer
  )
  precondition(sampleStatus == noErr, "Failed to create H264 sample buffer: \(sampleStatus)")
  return sampleBuffer!
}

/// Creates a BGRA CVPixelBuffer filled with a constant byte.
func makeBGRAPixelBuffer(width: Int, height: Int, fill: UInt8) -> CVPixelBuffer {
  let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
  var pixelBuffer: CVPixelBuffer?
  let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
  precondition(status == kCVReturnSuccess, "CVPixelBufferCreate failed: \(status)")
  let buffer = pixelBuffer!
  CVPixelBufferLockBaseAddress(buffer, [])
  if let base = CVPixelBufferGetBaseAddress(buffer) {
    memset(base, Int32(fill), CVPixelBufferGetDataSize(buffer))
  }
  CVPixelBufferUnlockBaseAddress(buffer, [])
  return buffer
}

/// Wraps a constant-filled BGRA pixel buffer in a CMSampleBuffer (image-buffer backed), as the
/// device's BGRA stream receives from the capture pipeline.
func makeBGRASampleBuffer(width: Int, height: Int, fill: UInt8) -> CMSampleBuffer {
  let pixelBuffer = makeBGRAPixelBuffer(width: width, height: height, fill: fill)
  var formatDescription: CMVideoFormatDescription?
  let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
  precondition(formatStatus == noErr, "CMVideoFormatDescriptionCreateForImageBuffer failed: \(formatStatus)")
  var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTimeMake(value: 0, timescale: 1), decodeTimeStamp: .invalid)
  var sampleBuffer: CMSampleBuffer?
  let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: formatDescription!, sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
  precondition(sampleStatus == noErr, "CMSampleBufferCreateReadyWithImageBuffer failed: \(sampleStatus)")
  return sampleBuffer!
}

/// Wraps JPEG bytes in a CMSampleBuffer whose data buffer is a CMBlockBuffer, as the device's
/// MJPEG/Minicap stream receives. When `width`/`height` are > 0 a JPEG video format description is
/// attached so consumers can read the dimensions (the Minicap header needs them).
func makeJPEGSampleBuffer(bytes: [UInt8], width: Int32 = 0, height: Int32 = 0) -> CMSampleBuffer {
  let blockBuffer = makeOwnedBlockBuffer(bytes)
  var formatDescription: CMFormatDescription?
  if width > 0, height > 0 {
    let formatStatus = CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_JPEG, width: width, height: height, extensions: nil, formatDescriptionOut: &formatDescription)
    precondition(formatStatus == noErr, "CMVideoFormatDescriptionCreate failed: \(formatStatus)")
  }
  var sampleSize = bytes.count
  var sampleBuffer: CMSampleBuffer?
  let sampleStatus = CMSampleBufferCreate(
    allocator: nil,
    dataBuffer: blockBuffer,
    dataReady: true,
    makeDataReadyCallback: nil,
    refcon: nil,
    formatDescription: formatDescription,
    sampleCount: 1,
    sampleTimingEntryCount: 0,
    sampleTimingArray: nil,
    sampleSizeEntryCount: 1,
    sampleSizeArray: &sampleSize,
    sampleBufferOut: &sampleBuffer
  )
  precondition(sampleStatus == noErr, "Failed to create JPEG sample buffer: \(sampleStatus)")
  return sampleBuffer!
}
