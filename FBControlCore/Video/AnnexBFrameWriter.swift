/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation

/// Annex-B byte stream: start-code-delimited NAL units, with the parameter sets repeated ahead of
/// every keyframe so a consumer can join at any keyframe.
public struct AnnexBFrameWriter: EncodedFrameWriter {
  private let codec: VideoStreamCodec

  public init(codec: VideoStreamCodec) {
    self.codec = codec
  }

  public func write(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) throws {
    if !CMSampleBufferDataIsReady(sampleBuffer) {
      throw EncodedFrameWriterError.sampleBufferNotReady
    }

    let isKeyFrame = sampleBuffer.isKeyFrame

    try AnnexB.replaceLengthPrefixes(in: sampleBuffer)

    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw EncodedFrameWriterError.failedToGetDataBuffer
    }

    // One write per frame: an async consumer counts writes against its drop threshold, so the
    // parameter sets a keyframe carries and the NAL data must arrive as a single item.
    var frame = Data()
    if isKeyFrame {
      guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        throw EncodedFrameWriterError.failedToGetFormatDescription
      }
      for parameterSet in try format.parameterSets(for: codec) {
        frame.append(contentsOf: AnnexB.startCode)
        frame.append(contentsOf: parameterSet)
      }
    }
    try dataBuffer.appendBytes(to: &frame)
    consumer.consumeData(frame)
  }
}
