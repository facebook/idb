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
/// transport writer (MPEG-TS ID3 or fMP4 `emsg`). This reproduces the pre-refactor inline transport
/// dispatch in `FBSimulatorVideoStream.writeTimedMetadata` exactly, including dropping (with a log) on
/// transports that carry no timed-metadata channel (e.g. Annex-B).
final class FBTransportTimedMetadataConsumer: FBTimedMetadataConsumer {
  private let format: FBVideoStreamFormat
  private let consumer: any FBDataConsumer
  /// The fMP4 muxer context (`FBFMP4MuxerContext`), shared with the owning stream so the `emsg` boxes
  /// mux into the same fragmented stream. `nil` for stateless transports (MPEG-TS, Annex-B).
  private let frameWriterContext: AnyObject?

  init(format: FBVideoStreamFormat, consumer: any FBDataConsumer, frameWriterContext: AnyObject?) {
    self.format = format
    self.consumer = consumer
    self.frameWriterContext = frameWriterContext
  }

  func writeTimedMetadata(_ text: String, logger: any FBControlCoreLogger) {
    if format.transport == .mpegts {
      FBMPEGTSEnableMetadataStream()
      FBMPEGTSWriteTimedMetadata(text, consumer)
    } else if format.transport == .fmp4 {
      if let ctx = frameWriterContext as? FBFMP4MuxerContext {
        FBFMP4WriteEmsgBox(ctx, text, consumer)
      }
    } else {
      logger.log("writeTimedMetadata: not supported for transport '\(String(describing: format.transport))', dropping")
    }
  }
}
