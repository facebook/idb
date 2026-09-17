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

class OverflownConsumerDouble: NSObject, DataConsumer, DataConsumerAsync {
  private var _unprocessedDataCount: Int = 0

  func unprocessedDataCount() -> Int {
    return _unprocessedDataCount
  }

  func setUnprocessedDataCount(_ value: Int) {
    _unprocessedDataCount = value
  }

  func consumeData(_ data: Data) {}

  func consumeEndOfFile() {}
}

// MARK: - Helpers

let defaultTestSPS: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
/// The default SPS at a different level, so a sample carrying it has a distinct format description.
let alternateTestSPS: [UInt8] = [0x67, 0x42, 0x00, 0x1e, 0xf8, 0x41, 0xa2]

func makeH264SampleBuffer(isKeyFrame: Bool, pts90k: Int64 = 0, sps: [UInt8] = defaultTestSPS) -> CMSampleBuffer {
  let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]
  let paramSizes: [Int] = [sps.count, pps.count]

  var formatDesc: CMFormatDescription?
  let status = sps.withUnsafeBufferPointer { spsPtr in
    pps.withUnsafeBufferPointer { ppsPtr in
      let paramSets: [UnsafePointer<UInt8>] = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
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
    presentationTimeStamp: CMTimeMake(value: pts90k, timescale: 90000),
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

  // Non-keyframes carry the NotSync attachment; keyframes omit it (modern VideoToolbox pattern).
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

func makeNotReadySampleBuffer() -> CMSampleBuffer {
  let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2]
  let pps: [UInt8] = [0x68, 0xce, 0x38, 0x80]
  let paramSizes: [Int] = [sps.count, pps.count]

  var formatDesc: CMFormatDescription?
  let status = sps.withUnsafeBufferPointer { spsPtr in
    pps.withUnsafeBufferPointer { ppsPtr in
      let paramSets: [UnsafePointer<UInt8>] = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
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

// Realistic HEVC (Main profile) VPS/SPS/PPS parameter sets, accepted by
// CMVideoFormatDescriptionCreateFromHEVCParameterSets. Used to build a genuine HEVC
// format description without pulling VideoToolbox into the FBControlCore test target.
let hevcVPS: [UInt8] = [
  0x40, 0x01, 0x0c, 0x01, 0xff, 0xff, 0x01, 0x60, 0x00, 0x00, 0x03, 0x00,
  0x90, 0x00, 0x00, 0x03, 0x00, 0x00, 0x03, 0x00, 0x78, 0x99, 0x98, 0x09,
]
let hevcSPS: [UInt8] = [
  0x42, 0x01, 0x01, 0x01, 0x60, 0x00, 0x00, 0x03, 0x00, 0x90, 0x00, 0x00,
  0x03, 0x00, 0x00, 0x03, 0x00, 0x78, 0xa0, 0x03, 0xc0, 0x80, 0x10, 0xe5,
  0x96, 0x56, 0x69, 0x24, 0xca, 0xe0, 0x10, 0x00, 0x00, 0x03, 0x00, 0x10,
  0x00, 0x00, 0x03, 0x01, 0xe0, 0x80,
]
let hevcPPS: [UInt8] = [
  0x44, 0x01, 0xc1, 0x72, 0xb4, 0x62, 0x40,
]

/// Returns nil if CoreMedia rejects the parameter sets, so the caller fails in isolation instead of crashing the bundle.
func makeHEVCSampleBuffer(isKeyFrame: Bool) -> CMSampleBuffer? {
  var formatDesc: CMFormatDescription?
  let formatStatus = hevcVPS.withUnsafeBufferPointer { vpsPtr in
    hevcSPS.withUnsafeBufferPointer { spsPtr in
      hevcPPS.withUnsafeBufferPointer { ppsPtr in
        // Order per spec convention: VPS, SPS, PPS.
        var paramSets: [UnsafePointer<UInt8>] = [vpsPtr.baseAddress!, spsPtr.baseAddress!, ppsPtr.baseAddress!]
        var paramSizes = [vpsPtr.count, spsPtr.count, ppsPtr.count]
        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
          allocator: nil,
          parameterSetCount: 3,
          parameterSetPointers: &paramSets,
          parameterSetSizes: &paramSizes,
          nalUnitHeaderLength: 4,
          extensions: nil,
          formatDescriptionOut: &formatDesc
        )
      }
    }
  }
  guard formatStatus == noErr, let format = formatDesc else {
    return nil
  }

  // AVCC NAL data: [4-byte big-endian length][HEVC IDR_W_RADL NAL]. NAL type 19 → header 0x26 0x01.
  let avccBytes: [UInt8] = [
    0x00, 0x00, 0x00, 0x06, // NAL length = 6
    0x26, 0x01, 0xaf, 0x08, 0x40, 0x00, // fake IDR slice
  ]
  let avccDataCount = avccBytes.count
  let avccPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: avccDataCount)
  avccBytes.withUnsafeBufferPointer { avccPtr.initialize(from: $0.baseAddress!, count: avccDataCount) }

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
  guard blockStatus == noErr else {
    return nil
  }

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
    formatDescription: format,
    sampleCount: 1,
    sampleTimingEntryCount: 1,
    sampleTimingArray: &timing,
    sampleSizeEntryCount: 1,
    sampleSizeArray: &sampleSize,
    sampleBufferOut: &sampleBuf
  )
  guard sampleStatus == noErr, let sampleBuffer = sampleBuf else {
    return nil
  }

  // Non-keyframes carry the NotSync attachment; keyframes omit it (modern VideoToolbox pattern).
  let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)!
  let attachments = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFMutableDictionary.self)
  if !isKeyFrame {
    CFDictionarySetValue(
      attachments,
      Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
      Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
    )
  }

  return sampleBuffer
}

/// Wraps the given bytes in a CMBlockBuffer for the JPEG-based frame writers.
func makeBlockBuffer(_ bytes: [UInt8]) -> CMBlockBuffer {
  let count = bytes.count
  let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
  bytes.withUnsafeBufferPointer { ptr.initialize(from: $0.baseAddress!, count: count) }

  var blockBuf: CMBlockBuffer?
  let status = CMBlockBufferCreateWithMemoryBlock(
    allocator: nil,
    memoryBlock: ptr,
    blockLength: count,
    blockAllocator: kCFAllocatorNull,
    customBlockSource: nil,
    offsetToData: 0,
    dataLength: count,
    flags: 0,
    blockBufferOut: &blockBuf
  )
  precondition(status == noErr, "Failed to create block buffer: \(status)")
  return blockBuf!
}

/// Counts the `consumeData` calls a writer makes, so a test can pin how many writes one frame costs.
final class CountingConsumer {
  private(set) var writes = 0
  private(set) var bytes = Data()
  private(set) lazy var consumer: any DataConsumer = FBBlockDataConsumer.synchronousDataConsumer { [weak self] data in
    self?.writes += 1
    self?.bytes.append(data)
  }
}

/// The TS packets in `data` carrying `pid`, each as its 188 bytes.
func tsPackets(_ data: Data, pid: UInt16) -> [Data] {
  var packets: [Data] = []
  var offset = 0
  while offset + 188 <= data.count {
    let packet = data.subdata(in: offset..<(offset + 188))
    let packetPID = (UInt16(packet[1] & 0x1F) << 8) | UInt16(packet[2])
    if packetPID == pid {
      packets.append(packet)
    }
    offset += 188
  }
  return packets
}

/// Returns the PID of every 188-byte TS packet in the data, in order.
func tsPacketPIDs(_ data: Data) -> [UInt16] {
  let bytes = [UInt8](data)
  var pids: [UInt16] = []
  var i = 0
  while i + 188 <= bytes.count {
    pids.append((UInt16(bytes[i + 1] & 0x1F) << 8) | UInt16(bytes[i + 2]))
    i += 188
  }
  return pids
}

enum FMP4BoxTestError: Error {
  case malformed(String)
}

let fmp4ContainerHeaderSizes: [String: Int] = [
  "moov": 8,
  "trak": 8,
  "mdia": 8,
  "minf": 8,
  "dinf": 8,
  "dref": 16,
  "stbl": 8,
  "stsd": 16,
  "avc1": 86,
  "hvc1": 86,
  "mvex": 8,
  "moof": 8,
  "traf": 8,
]

func fmp4BoxSignatures(_ data: Data, in range: Range<Int>, parentPath: String = "") throws -> [String] {
  var signatures = [String]()
  var offset = range.lowerBound

  while offset < range.upperBound {
    guard offset + 8 <= range.upperBound else {
      throw FMP4BoxTestError.malformed("Incomplete box header at offset \(offset)")
    }

    let size = data.withUnsafeBytes { bytes in
      Int(UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
    }
    guard size >= 8, offset + size <= range.upperBound else {
      throw FMP4BoxTestError.malformed("Invalid box size \(size) at offset \(offset)")
    }

    let typeData = data.subdata(in: offset + 4..<offset + 8)
    guard let type = String(data: typeData, encoding: .utf8) else {
      throw FMP4BoxTestError.malformed("Invalid box type at offset \(offset)")
    }

    let path = parentPath.isEmpty ? type : "\(parentPath)/\(type)"
    signatures.append("\(path):\(size)")

    if let headerSize = fmp4ContainerHeaderSizes[type] {
      signatures.append(contentsOf: try fmp4BoxSignatures(data, in: offset + headerSize..<offset + size, parentPath: path))
    }
    offset += size
  }

  return signatures
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
  let blockBuffer = makeBlockBuffer(bytes)
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
