/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import FBControlCore
import Foundation

// MARK: - FBVideoFileWriter

/// Muxes already-encoded H264/HEVC `CMSampleBuffer`s into an `.mp4` using `AVAssetWriter` in
/// passthrough mode (no re-encode). The in-process simulator recorder uses this as the file sink for
/// the framebuffer→VideoToolbox encode pipeline.
///
/// The writer opens lazily on its first sample, rather than being prepared up front: passthrough
/// muxing needs that sample's `CMFormatDescription` as the `sourceFormatHint` before `AVAssetWriter`
/// can start writing, and the encoded format only exists once the encoder emits its first frame. Only
/// that first frame incurs the one-time setup and it is still appended (not dropped); `consume` runs
/// serially, so later frames never overlap it and append directly. The movie timeline is anchored at
/// the first sample's presentation timestamp; `finish`, called once after the encoder has flushed,
/// finalizes the `moov`.
///
/// @unchecked Sendable: like its sibling pushers all access is confined to a single serial queue
/// (the owning stream's `writeQueue`, with which the VideoToolbox output handler runs serially), and
/// `finish` is only called after the encoder has completed every frame, so `consume` and `finish`
/// never overlap.
final class FBVideoFileWriter: NSObject, FBEncodedSampleConsumer, @unchecked Sendable {
  private let outputURL: URL
  private let fileType: AVFileType
  private let logger: any FBControlCoreLogger

  private var assetWriter: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var failed = false

  init(filePath: String, fileType: AVFileType = .mp4, logger: any FBControlCoreLogger) {
    self.outputURL = URL(fileURLWithPath: filePath)
    self.fileType = fileType
    self.logger = logger
    super.init()
  }

  // MARK: - FBEncodedSampleConsumer

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any FBControlCoreLogger) -> Bool {
    if failed {
      return false
    }
    let input: AVAssetWriterInput
    do {
      input = try startIfNeeded(with: sampleBuffer)
    } catch {
      failed = true
      logger.log("AVAssetWriter failed to start: \(error)")
      return false
    }
    // Never block the encode queue: if the writer is behind, drop the frame. The encoder counts the
    // returned `false` as a write failure, matching the streaming consumer-overflow behavior.
    guard input.isReadyForMoreMediaData else {
      logger.log("AVAssetWriter input not ready for more media data, dropping frame")
      return false
    }
    guard input.append(sampleBuffer) else {
      failed = true
      logger.log("AVAssetWriter failed to append sample: \(assetWriter?.error.map { String(describing: $0) } ?? "unknown error")")
      return false
    }
    return true
  }

  // MARK: - Lifecycle

  /// Finalize the file: mark the input finished and await `finishWriting`. Call once, after the
  /// encoder has flushed all pending frames. A no-op if no frame was ever written.
  func finish() async throws {
    guard let assetWriter, let input else {
      logger.log("FBVideoFileWriter.finish called with no frames written; nothing to finalize")
      return
    }
    input.markAsFinished()
    await assetWriter.finishWriting()
    if assetWriter.status == .failed {
      throw FBControlCoreError.describe("AVAssetWriter failed to finish writing: \(assetWriter.error.map { String(describing: $0) } ?? "unknown error")").build()
    }
  }

  // MARK: - Private

  private func startIfNeeded(with sampleBuffer: CMSampleBuffer) throws -> AVAssetWriterInput {
    if let input {
      return input
    }
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      throw FBControlCoreError.describe("First sample buffer has no format description").build()
    }
    // AVAssetWriter refuses to overwrite an existing file.
    try? FileManager.default.removeItem(at: outputURL)

    let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
    input.expectsMediaDataInRealTime = true
    guard assetWriter.canAdd(input) else {
      throw FBControlCoreError.describe("AVAssetWriter cannot add the video input").build()
    }
    assetWriter.add(input)
    guard assetWriter.startWriting() else {
      throw FBControlCoreError.describe("AVAssetWriter failed to start writing: \(assetWriter.error.map { String(describing: $0) } ?? "unknown error")").build()
    }
    assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    self.assetWriter = assetWriter
    self.input = input
    return input
  }
}
