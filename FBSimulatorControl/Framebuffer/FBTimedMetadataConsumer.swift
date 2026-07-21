/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - FBTimedMetadataConsumer

/// A sink for the timed-metadata (chapter) markers emitted mid-stream by
/// `FBSimulatorVideoStream.writeTimedMetadata`. Decoupling the marker write from the transport lets the
/// same framebuffer→VideoToolbox pipeline target either a streaming byte consumer (fMP4 `emsg` /
/// MPEG-TS ID3, the `stream` command) or an `AVAssetWriter` chapter track (the `record` command),
/// without the stream knowing which — mirroring how `FBEncodedSampleConsumer` decouples the
/// encoded-frame sink.
protocol FBTimedMetadataConsumer: AnyObject {
  /// Write a single timed-metadata marker for the current stream position.
  func writeTimedMetadata(_ text: String, logger: any FBControlCoreLogger)
}

// MARK: - FBTransportTimedMetadataConsumer

/// The streaming `FBTimedMetadataConsumer`: muxes each marker into the encoded byte stream via the
/// transport writer (MPEG-TS ID3 or fMP4 `emsg`). Transports that carry no timed-metadata channel
/// (e.g. Annex-B) pass `nil` and drop markers with a log.
final class FBTransportTimedMetadataConsumer: FBTimedMetadataConsumer {
  private let consumer: any FBDataConsumer
  /// Transport writer that can mux timed metadata into the same byte stream. `nil` for stateless
  /// transports (Annex-B).
  private let timedMetadataWriter: (any FBVideoStreamTimedMetadataWriter)?

  init(consumer: any FBDataConsumer, timedMetadataWriter: (any FBVideoStreamTimedMetadataWriter)?) {
    self.consumer = consumer
    self.timedMetadataWriter = timedMetadataWriter
  }

  func writeTimedMetadata(_ text: String, logger: any FBControlCoreLogger) {
    guard let timedMetadataWriter else {
      logger.log("writeTimedMetadata: not supported for this transport, dropping")
      return
    }
    timedMetadataWriter.writeTimedMetadata(text, to: consumer)
  }
}
