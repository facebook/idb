/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import FBControlCore
import FBVideoCore
import Foundation
import os

// MARK: - SimulatorVideoWebMWriter

/// Writes a recording's encoded H.264 or HEVC samples to a WebM file through `WebMFileWriter`. The file can change
/// frame size mid-recording, so a recording into it follows the screen through rotations and display switches rather
/// than letterboxing into its first frame.
///
/// Chapter markers are buffered at the current video position and written as the file's chapters by `finish`.
///
/// @unchecked Sendable: `consume` runs inside the VideoToolbox output handler, which a session invokes serially, and
/// `finish` is called once, after `stopStreaming` has flushed the encoder, so the file writer is only ever used
/// serially. `writeTimedMetadata` arrives from other isolation domains (the stdin handler), so the chapter state it
/// shares with `consume` and `finish` lives under a lock, as does the anchor the recorder reads.
final class SimulatorVideoWebMWriter: RecordingFileWriter, @unchecked Sendable {
  let carriesFrameSizeChanges = true

  private let writer: WebMFileWriter
  private let chaptersEnabled: Bool
  private let logger: any ControlCoreLogger
  private var failed = false

  private struct ChapterState {
    var pendingChapters: [(title: String, time: CMTime)] = []
    var lastPresentationTime: CMTime = .invalid
  }
  private let chapters = OSAllocatedUnfairLock(initialState: ChapterState())
  private let anchor = OSAllocatedUnfairLock(initialState: CMTime.invalid)

  var startPresentationTime: CMTime? {
    let time = anchor.withLock { $0 }
    return time.isValid ? time : nil
  }

  init(filePath: String, chaptersEnabled: Bool = false, logger: any ControlCoreLogger) {
    self.writer = WebMFileWriter(fileURL: URL(fileURLWithPath: filePath))
    self.chaptersEnabled = chaptersEnabled
    self.logger = logger
  }

  // MARK: - EncodedSampleConsumer

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any ControlCoreLogger) -> Bool {
    if failed {
      return false
    }
    do {
      guard try writer.write(sampleBuffer) else {
        return false
      }
    } catch {
      failed = true
      logger.log("Failed to write a sample to the WebM recording: \(error)")
      return false
    }
    if let start = writer.startPresentationTime {
      anchor.withLock { if !$0.isValid { $0 = start } }
    }
    if chaptersEnabled {
      let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      chapters.withLock { $0.lastPresentationTime = time }
    }
    return true
  }

  // MARK: - TimedMetadataConsumer

  /// Buffers a chapter marker at the most recent frame, or at the start of the file before the first.
  func writeTimedMetadata(_ text: String, logger: any ControlCoreLogger) {
    guard chaptersEnabled else {
      logger.log("writeTimedMetadata: chapters not enabled on this recording, dropping")
      return
    }
    chapters.withLock { state in
      state.pendingChapters.append((title: text, time: state.lastPresentationTime))
    }
  }

  // MARK: - RecordingFileWriter

  func finish() async throws {
    guard writer.startPresentationTime != nil else {
      logger.log("SimulatorVideoWebMWriter.finish called with no frames written; nothing to finalize")
      return
    }
    try writer.finish(chapters: chapters.withLock { $0.pendingChapters })
  }
}
