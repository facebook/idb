/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import FBControlCore
import Foundation

/// MJPEG streaming: each encoded JPEG's bytes go to the consumer as they are, back to back.
final class MJPEGSampleConsumer: EncodedSampleConsumer {
  private let consumer: any DataConsumer
  private let writer = MJPEGFrameWriter()

  init(consumer: any DataConsumer) {
    self.consumer = consumer
  }

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any ControlCoreLogger) -> Bool {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      return false
    }
    do {
      try writer.write(blockBuffer, to: consumer, logger: logger)
      return true
    } catch {
      logger.log("Failed to write MJPEG frame: \(error)")
      return false
    }
  }
}

/// Minicap streaming: the global header, sized from the first sample's format, then each JPEG
/// prefixed with its length.
final class MinicapSampleConsumer: EncodedSampleConsumer {
  private let consumer: any DataConsumer
  private let writer = MinicapFrameWriter()
  private var hasWrittenHeader = false

  init(consumer: any DataConsumer) {
    self.consumer = consumer
  }

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any ControlCoreLogger) -> Bool {
    if !hasWrittenHeader, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
      let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
      writer.writeHeader(width: UInt32(dimensions.width), height: UInt32(dimensions.height), to: consumer, logger: logger)
      hasWrittenHeader = true
    }
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      return false
    }
    do {
      try writer.write(blockBuffer, to: consumer, logger: logger)
      return true
    } catch {
      logger.log("Failed to write Minicap frame: \(error)")
      return false
    }
  }
}
