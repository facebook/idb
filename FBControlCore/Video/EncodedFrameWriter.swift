/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation

let AVCCHeaderLength: Int = 4
let AnnexBStartCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

public protocol EncodedFrameWriter {
  func write(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) throws
}

public protocol VideoStreamTimedMetadataWriter {
  func writeTimedMetadata(_ text: String, to consumer: any DataConsumer)
}

public struct VideoStreamFrameWriters {
  public let frameWriter: any EncodedFrameWriter
  public let timedMetadataWriter: (any VideoStreamTimedMetadataWriter)?

  public init(frameWriter: any EncodedFrameWriter, timedMetadataWriter: (any VideoStreamTimedMetadataWriter)?) {
    self.frameWriter = frameWriter
    self.timedMetadataWriter = timedMetadataWriter
  }
}

public extension VideoStreamTransport {
  func frameWriters(for codec: VideoStreamCodec) -> VideoStreamFrameWriters {
    switch self {
    case .fmp4:
      let writer = FMP4FrameWriter(codec: codec)
      return VideoStreamFrameWriters(frameWriter: writer, timedMetadataWriter: writer)
    case .mpegts:
      let writer = MPEGTSFrameWriter(codec: codec)
      return VideoStreamFrameWriters(frameWriter: writer, timedMetadataWriter: writer)
    case .annexB:
      return VideoStreamFrameWriters(frameWriter: AnnexBFrameWriter(codec: codec), timedMetadataWriter: nil)
    }
  }
}

enum VideoStreamWriterError: Error {
  case failedToGetDataPointer(offset: Int, status: OSStatus)
  case failedToGetDataBuffer
  case failedToAccessBlockBufferData(offset: Int, status: OSStatus)
  case failedToReplaceBlockBufferData(offset: Int, status: OSStatus)
  case sampleBufferNotReady
  case failedToGetFormatDescription
  case failedToGetParameterSetCount(codecName: String, status: OSStatus)
  case failedToGetParameterSet(codecName: String, index: Int, status: OSStatus)
  case failedToCopyBlockBufferData(status: OSStatus)
}

extension VideoStreamWriterError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case let .failedToGetDataPointer(offset, status):
      return "Failed to get Data Pointer at offset \(offset): \(status)"
    case .failedToGetDataBuffer:
      return "Failed to get data buffer"
    case let .failedToAccessBlockBufferData(offset, status):
      return "Failed to access block buffer data at offset \(offset): \(status)"
    case let .failedToReplaceBlockBufferData(offset, status):
      return "Failed to replace block buffer data at offset \(offset): \(status)"
    case .sampleBufferNotReady:
      return "Sample Buffer is not ready"
    case .failedToGetFormatDescription:
      return "Failed to get format description"
    case let .failedToGetParameterSetCount(codecName, status):
      return "Failed to get \(codecName) parameter set count \(status)"
    case let .failedToGetParameterSet(codecName, index, status):
      return "Failed to get \(codecName) parameter set at index \(index): \(status)"
    case let .failedToCopyBlockBufferData(status):
      return "Failed to copy block buffer data: \(status)"
    }
  }
}

/// Sync consumers receive zero-copy Data backed by the block buffer; async consumers receive a copy.
func WriteBlockBufferToConsumer(_ blockBuffer: CMBlockBuffer, _ consumer: any DataConsumer) throws {
  let dataLength = CMBlockBufferGetDataLength(blockBuffer)
  let isSyncConsumer = consumer is DataConsumerSync
  var offset = 0
  while offset < dataLength {
    var dataPointer: UnsafeMutablePointer<CChar>?
    var lengthAtOffset = 0
    let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: offset, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: nil, dataPointerOut: &dataPointer)
    if status != noErr {
      throw VideoStreamWriterError.failedToGetDataPointer(offset: offset, status: status)
    }
    guard let dataPointer else {
      throw VideoStreamWriterError.failedToGetDataPointer(offset: offset, status: status)
    }
    if isSyncConsumer {
      consumer.consumeData(Data(bytesNoCopy: dataPointer, count: lengthAtOffset, deallocator: .none))
    } else {
      consumer.consumeData(Data(bytes: dataPointer, count: lengthAtOffset))
    }
    offset += lengthAtOffset
  }
}

func ConvertAVCCToAnnexBInPlace(_ sampleBuffer: CMSampleBuffer) throws {
  guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
    throw VideoStreamWriterError.failedToGetDataBuffer
  }
  let dataLength = CMBlockBufferGetDataLength(dataBuffer)

  var offset = 0
  while offset < dataLength - AVCCHeaderLength {
    var nalLengthBuf = [UInt8](repeating: 0, count: AVCCHeaderLength)
    var nalLengthPtr: UnsafeMutablePointer<CChar>?
    var status = nalLengthBuf.withUnsafeMutableBytes { temp -> OSStatus in
      guard let tempBase = temp.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
      return CMBlockBufferAccessDataBytes(dataBuffer, atOffset: offset, length: AVCCHeaderLength, temporaryBlock: tempBase, returnedPointerOut: &nalLengthPtr)
    }
    if status != noErr {
      throw VideoStreamWriterError.failedToAccessBlockBufferData(offset: offset, status: status)
    }
    // The AVCC NAL length prefix is big-endian.
    var nalLength: UInt32 = 0
    if let nalLengthPtr {
      nalLengthPtr.withMemoryRebound(to: UInt8.self, capacity: AVCCHeaderLength) { bytes in
        nalLength = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
      }
    }
    status = AnnexBStartCode.withUnsafeBytes { ptr -> OSStatus in
      guard let startBase = ptr.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
      return CMBlockBufferReplaceDataBytes(with: startBase, blockBuffer: dataBuffer, offsetIntoDestination: offset, dataLength: AVCCHeaderLength)
    }
    if status != noErr {
      throw VideoStreamWriterError.failedToReplaceBlockBufferData(offset: offset, status: status)
    }
    offset += AVCCHeaderLength + Int(nalLength)
  }
}

// H264 and HEVC parameter set getters have identical signatures.
typealias VideoParameterSetGetter = (
  _ formatDescription: CMFormatDescription,
  _ parameterSetIndex: Int,
  _ parameterSetPointerOut: UnsafeMutablePointer<UnsafePointer<UInt8>?>?,
  _ parameterSetSizeOut: UnsafeMutablePointer<Int>?,
  _ parameterSetCountOut: UnsafeMutablePointer<Int>?,
  _ nalUnitHeaderLengthOut: UnsafeMutablePointer<Int32>?
) -> OSStatus

extension VideoStreamCodec {
  var parameterSetGetter: VideoParameterSetGetter {
    switch self {
    case .h264:
      return CMVideoFormatDescriptionGetH264ParameterSetAtIndex
    case .hevc:
      return CMVideoFormatDescriptionGetHEVCParameterSetAtIndex
    }
  }

  var displayName: String {
    switch self {
    case .h264:
      return "H264"
    case .hevc:
      return "HEVC"
    }
  }
}

func FBVideoSampleBufferIsKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
  guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true), CFArrayGetCount(attachments) != 0 else {
    return false
  }
  let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
  return !CFDictionaryContainsKey(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
}

func AppendBlockBuffer(_ blockBuffer: CMBlockBuffer, length: Int, to data: inout Data) throws {
  let offset = data.count
  data.append(contentsOf: [UInt8](repeating: 0, count: length))
  let status = data.withUnsafeMutableBytes { bytes -> OSStatus in
    guard let base = bytes.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
    return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base + offset)
  }
  if status != noErr {
    throw VideoStreamWriterError.failedToCopyBlockBufferData(status: status)
  }
}
