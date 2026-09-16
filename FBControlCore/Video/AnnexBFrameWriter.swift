/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation

public struct AnnexBFrameWriter: EncodedFrameWriter {
  private let codec: VideoStreamCodec

  public init(codec: VideoStreamCodec) {
    self.codec = codec
  }

  public func write(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) throws {
    if !CMSampleBufferDataIsReady(sampleBuffer) {
      throw VideoStreamWriterError.sampleBufferNotReady
    }

    let isKeyFrame = FBVideoSampleBufferIsKeyFrame(sampleBuffer)

    try ConvertAVCCToAnnexBInPlace(sampleBuffer)

    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw VideoStreamWriterError.failedToGetDataBuffer
    }

    // One write per frame: an async consumer counts writes against its drop threshold, so the
    // parameter sets a keyframe carries and the NAL data must arrive as a single item.
    let dataLength = CMBlockBufferGetDataLength(dataBuffer)
    var frame = Data()
    if isKeyFrame {
      // Keyframes: parameter sets (SPS, PPS / VPS, SPS, PPS) first, then the converted block buffer.
      guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        throw VideoStreamWriterError.failedToGetFormatDescription
      }
      var parameterSetCount = 0
      var status = codec.parameterSetGetter(format, 0, nil, nil, &parameterSetCount, nil)
      if status != noErr {
        throw VideoStreamWriterError.failedToGetParameterSetCount(codecName: codec.displayName, status: status)
      }
      for i in 0..<parameterSetCount {
        var paramSize = 0
        var parameterSet: UnsafePointer<UInt8>?
        status = codec.parameterSetGetter(format, i, &parameterSet, &paramSize, nil, nil)
        if status != noErr {
          throw VideoStreamWriterError.failedToGetParameterSet(codecName: codec.displayName, index: i, status: status)
        }
        frame.append(contentsOf: AnnexBStartCode)
        if let parameterSet {
          frame.append(parameterSet, count: paramSize)
        }
      }
    }
    try AppendBlockBuffer(dataBuffer, length: dataLength, to: &frame)
    consumer.consumeData(frame)
  }
}
