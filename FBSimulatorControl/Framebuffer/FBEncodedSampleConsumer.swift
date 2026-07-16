/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import FBControlCore
import Foundation

// MARK: - FBEncodedSampleConsumer

/// A sink for the encoded H264/HEVC `CMSampleBuffer`s produced by the VideoToolbox pusher's
/// `.compressed` output. Decoupling the per-sample output from `FBDataConsumer` byte-framing lets the
/// same framebuffer→VideoToolbox encode pipeline target either a streaming byte consumer (the `stream`
/// command) or an `AVAssetWriter`-backed file (the `record` command), without the pipeline knowing
/// which.
protocol FBEncodedSampleConsumer: AnyObject {
  /// Consume a single encoded sample. Returns whether the write succeeded — the VideoToolbox pusher
  /// uses this to drive its write / failure / starvation stats exactly as the former inline
  /// `frameWriter` return value did.
  func consume(_ sampleBuffer: CMSampleBuffer, logger: any FBControlCoreLogger) -> Bool
}

// MARK: - FBDataConsumerEncodedSampleConsumer

/// The streaming `FBEncodedSampleConsumer`: byte-frames each encoded sample to an `FBDataConsumer`
/// through an `FBCompressedFrameWriter` (Annex-B / MPEG-TS / fMP4). This reproduces the pre-refactor
/// inline frame writer call exactly.
final class FBDataConsumerEncodedSampleConsumer: FBEncodedSampleConsumer {
  let consumer: any FBDataConsumer
  let frameWriter: FBCompressedFrameWriter
  /// The muxer context (e.g. `FBFMP4MuxerContext` for fMP4), shared with the owning stream so its
  /// `writeTimedMetadata` emsg/ID3 path muxes into the same stream. `nil` for stateless transports.
  let frameWriterContext: AnyObject?

  init(consumer: any FBDataConsumer, frameWriter: @escaping FBCompressedFrameWriter, frameWriterContext: AnyObject?) {
    self.consumer = consumer
    self.frameWriter = frameWriter
    self.frameWriterContext = frameWriterContext
  }

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any FBControlCoreLogger) -> Bool {
    do {
      try frameWriter(sampleBuffer, frameWriterContext, consumer, logger)
      return true
    } catch {
      logger.log("Failed to write encoded sample: \(error)")
      return false
    }
  }
}
