/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import FBControlCore
import Foundation

// MARK: - EncodedSampleConsumer

/// A sink for the `CMSampleBuffer`s the VideoToolbox pusher produces. Decoupling the per-sample
/// output from `DataConsumer` byte-framing lets the same framebuffer→VideoToolbox encode pipeline
/// target either a streaming byte consumer (the `stream` command) or an `AVAssetWriter`-backed file
/// (the `record` command), without the pipeline knowing which.
protocol EncodedSampleConsumer: AnyObject {
  /// Consume a single encoded sample. The return value feeds the pusher's write / failure / starvation stats.
  func consume(_ sampleBuffer: CMSampleBuffer, logger: any ControlCoreLogger) -> Bool
}

// MARK: - DataConsumerEncodedSampleConsumer

/// The streaming `EncodedSampleConsumer`: byte-frames each sample to a `DataConsumer` through the
/// format's `EncodedFrameWriter` (Annex-B / MPEG-TS / fMP4 / MJPEG / Minicap).
final class DataConsumerEncodedSampleConsumer: EncodedSampleConsumer {
  let consumer: any DataConsumer
  let frameWriter: any EncodedFrameWriter

  init(consumer: any DataConsumer, frameWriter: any EncodedFrameWriter) {
    self.consumer = consumer
    self.frameWriter = frameWriter
  }

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any ControlCoreLogger) -> Bool {
    do {
      try frameWriter.write(sampleBuffer, to: consumer, logger: logger)
      return true
    } catch {
      logger.log("Failed to write encoded sample: \(error)")
      return false
    }
  }
}
