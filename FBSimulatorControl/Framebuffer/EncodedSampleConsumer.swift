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

/// A sink for the encoded H264/HEVC `CMSampleBuffer`s produced by the VideoToolbox pusher's
/// `.compressed` output. Decoupling the per-sample output from `FBDataConsumer` byte-framing lets the
/// same framebuffer→VideoToolbox encode pipeline target either a streaming byte consumer (the `stream`
/// command) or an `AVAssetWriter`-backed file (the `record` command), without the pipeline knowing
/// which.
protocol EncodedSampleConsumer: AnyObject {
  /// Consume a single encoded sample. The return value feeds the pusher's write / failure / starvation stats.
  func consume(_ sampleBuffer: CMSampleBuffer, logger: any FBControlCoreLogger) -> Bool
}

// MARK: - DataConsumerEncodedSampleConsumer

/// The streaming `EncodedSampleConsumer`: byte-frames each encoded sample to an `FBDataConsumer`
/// through an `EncodedFrameWriter` (Annex-B / MPEG-TS / fMP4).
final class DataConsumerEncodedSampleConsumer: EncodedSampleConsumer {
  let consumer: any FBDataConsumer
  let frameWriter: any EncodedFrameWriter
  /// The timed-metadata writer for transports that can carry markers (`fMP4` / `MPEG-TS`).
  let timedMetadataWriter: (any VideoStreamTimedMetadataWriter)?

  init(consumer: any FBDataConsumer, frameWriter: any EncodedFrameWriter, timedMetadataWriter: (any VideoStreamTimedMetadataWriter)?) {
    self.consumer = consumer
    self.frameWriter = frameWriter
    self.timedMetadataWriter = timedMetadataWriter
  }

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any FBControlCoreLogger) -> Bool {
    do {
      try frameWriter.write(sampleBuffer, to: consumer, logger: logger)
      return true
    } catch {
      logger.log("Failed to write encoded sample: \(error)")
      return false
    }
  }
}
