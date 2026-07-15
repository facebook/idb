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

// MARK: - FBSimulatorVideoFileWriter

private enum FBSimulatorVideoFileWriterError: Error {
  case assetWriterFailedToFinish(errorDescription: String)
  case firstSampleBufferMissingFormatDescription
  case cannotAddVideoInput
  case assetWriterFailedToStart(errorDescription: String)
}

extension FBSimulatorVideoFileWriterError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .assetWriterFailedToFinish(let errorDescription):
      return "AVAssetWriter failed to finish writing: \(errorDescription)"
    case .firstSampleBufferMissingFormatDescription:
      return "First sample buffer has no format description"
    case .cannotAddVideoInput:
      return "AVAssetWriter cannot add the video input"
    case .assetWriterFailedToStart(let errorDescription):
      return "AVAssetWriter failed to start writing: \(errorDescription)"
    }
  }
}

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
/// When `chaptersEnabled` is set, the writer also adds a QuickTime chapter track — a `.text` track
/// associated with the video track via `chapterList` — and conforms to `FBTimedMetadataConsumer` so
/// `FBSimulatorVideoStream.writeTimedMetadata` markers become player-visible chapters. Markers are
/// buffered as they arrive (timestamped at the current video position) and written as text samples in
/// `finish`, once every chapter's end boundary (the next chapter, or the end of video) is known.
///
/// @unchecked Sendable: the encoded-frame path (`consume`/`finish`) is confined to the owning stream's
/// `writeQueue` (with which the VideoToolbox output handler runs serially), and `finish` is only
/// called after the encoder has completed every frame, so `consume` and `finish` never overlap. The
/// timed-metadata path (`writeTimedMetadata`) runs off that queue (the stdin handler), so the chapter
/// state it shares with `consume`/`finish` is guarded by `chapterLock`.
final class FBSimulatorVideoFileWriter: NSObject, FBEncodedSampleConsumer, FBTimedMetadataConsumer, @unchecked Sendable {
  private let outputURL: URL
  private let fileType: AVFileType
  private let chaptersEnabled: Bool
  private let logger: any FBControlCoreLogger

  private var assetWriter: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var chapterInput: AVAssetWriterInput?
  private var chapterFormatDescription: CMFormatDescription?
  private var failed = false

  /// Chapter markers and the running video position, shared between the writeQueue (`consume`/`finish`)
  /// and the stdin handler (`writeTimedMetadata`); guarded by `chapterLock`.
  private let chapterLock = NSLock()
  private var pendingChapters: [(time: CMTime, text: String)] = []
  private var firstPresentationTime: CMTime = .invalid
  private var lastPresentationTime: CMTime = .invalid

  init(filePath: String, fileType: AVFileType = .mp4, chaptersEnabled: Bool = false, logger: any FBControlCoreLogger) {
    self.outputURL = URL(fileURLWithPath: filePath)
    self.fileType = fileType
    self.chaptersEnabled = chaptersEnabled
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
    if chaptersEnabled {
      recordVideoPosition(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
    return true
  }

  // MARK: - FBTimedMetadataConsumer

  /// Buffer a chapter marker at the current video position. Written to the chapter track in `finish`.
  func writeTimedMetadata(_ text: String, logger: any FBControlCoreLogger) {
    guard chaptersEnabled else {
      logger.log("writeTimedMetadata: chapters not enabled on this recording, dropping")
      return
    }
    chapterLock.lock()
    defer { chapterLock.unlock() }
    // Timestamp the marker at the most recent frame; if none yet, anchor at the session start (filled
    // in once the first frame arrives) by using .invalid, resolved at finish.
    let time = lastPresentationTime.isValid ? lastPresentationTime : firstPresentationTime
    pendingChapters.append((time: time, text: text))
  }

  // MARK: - Lifecycle

  /// Finalize the file: mark the inputs finished and await `finishWriting`. Call once, after the
  /// encoder has flushed all pending frames. A no-op if no frame was ever written.
  func finish() async throws {
    guard let assetWriter, let input else {
      logger.log("FBSimulatorVideoFileWriter.finish called with no frames written; nothing to finalize")
      return
    }
    if let chapterInput {
      writeBufferedChapters(into: chapterInput)
      chapterInput.markAsFinished()
    }
    input.markAsFinished()
    await assetWriter.finishWriting()
    if assetWriter.status == .failed {
      throw FBSimulatorVideoFileWriterError.assetWriterFailedToFinish(errorDescription: assetWriter.error.map { String(describing: $0) } ?? "unknown error")
    }
  }

  // MARK: - Private

  private func recordVideoPosition(_ time: CMTime) {
    chapterLock.lock()
    defer { chapterLock.unlock() }
    if !firstPresentationTime.isValid {
      firstPresentationTime = time
    }
    lastPresentationTime = time
  }

  private func startIfNeeded(with sampleBuffer: CMSampleBuffer) throws -> AVAssetWriterInput {
    if let input {
      return input
    }
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      throw FBSimulatorVideoFileWriterError.firstSampleBufferMissingFormatDescription
    }
    // AVAssetWriter refuses to overwrite an existing file.
    try? FileManager.default.removeItem(at: outputURL)

    let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
    input.expectsMediaDataInRealTime = true
    guard assetWriter.canAdd(input) else {
      throw FBSimulatorVideoFileWriterError.cannotAddVideoInput
    }
    assetWriter.add(input)

    // A chapter track must be created and associated before `startWriting`. If the text format
    // description cannot be built, degrade to a chapterless recording rather than failing.
    if chaptersEnabled {
      addChapterTrack(to: assetWriter, associatedWith: input)
    }

    guard assetWriter.startWriting() else {
      throw FBSimulatorVideoFileWriterError.assetWriterFailedToStart(errorDescription: assetWriter.error.map { String(describing: $0) } ?? "unknown error")
    }
    assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    self.assetWriter = assetWriter
    self.input = input
    return input
  }

  private func addChapterTrack(to assetWriter: AVAssetWriter, associatedWith videoInput: AVAssetWriterInput) {
    guard let formatDescription = Self.makeChapterTextFormatDescription() else {
      logger.log("Failed to build chapter text format description; recording without chapters")
      return
    }
    let chapterInput = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: formatDescription)
    chapterInput.expectsMediaDataInRealTime = false
    // Tag the chapter titles as language-undetermined; players and `ffprobe -show_chapters` group
    // chapters by language, and an untagged track is skipped by AVFoundation's language-filtered reader.
    chapterInput.languageCode = "und"
    guard assetWriter.canAdd(chapterInput) else {
      logger.log("AVAssetWriter cannot add the chapter text input; recording without chapters")
      return
    }
    assetWriter.add(chapterInput)
    videoInput.addTrackAssociation(withTrackOf: chapterInput, type: AVAssetTrack.AssociationType.chapterList.rawValue)
    self.chapterInput = chapterInput
    self.chapterFormatDescription = formatDescription
  }

  /// Drain the buffered markers into the chapter input as text samples with contiguous time ranges:
  /// each chapter runs until the next one, and the last until the end of the recorded video.
  private func writeBufferedChapters(into chapterInput: AVAssetWriterInput) {
    chapterLock.lock()
    let chapters = pendingChapters
    let sessionStart = firstPresentationTime
    let videoEnd = lastPresentationTime
    chapterLock.unlock()

    guard let formatDescription = chapterFormatDescription, !chapters.isEmpty else {
      return
    }
    let resolved = chapters.map { (time: $0.time.isValid ? $0.time : sessionStart, text: $0.text) }
    let minDuration = CMTimeMake(value: 1, timescale: 600)
    for (index, chapter) in resolved.enumerated() {
      let start = chapter.time
      let rawEnd = index + 1 < resolved.count ? resolved[index + 1].time : videoEnd
      var duration = CMTimeSubtract(rawEnd, start)
      if !duration.isValid || duration <= .zero {
        duration = minDuration
      }
      guard let sample = Self.makeChapterSampleBuffer(text: chapter.text, formatDescription: formatDescription, time: start, duration: duration) else {
        logger.log("Failed to build chapter sample for '\(chapter.text)', skipping")
        continue
      }
      if !chapterInput.isReadyForMoreMediaData || !chapterInput.append(sample) {
        logger.log("Failed to append chapter sample for '\(chapter.text)'")
      }
    }
  }

  // MARK: - QuickTime Text Track Construction

  /// Build a QuickTime `'text'` sample description (the layout of the classic `TextDescription` struct
  /// from `Movies.h`, big-endian) and wrap it in a `CMTextFormatDescription`. The visual style fields
  /// are inert — chapter titles surface in player chapter menus, not as rendered captions.
  private static func makeChapterTextFormatDescription() -> CMFormatDescription? {
    var data = [UInt8]()
    func appendBE32(_ value: UInt32) {
      data.append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
    func appendBE16(_ value: UInt16) {
      data.append(contentsOf: [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    appendBE32(0) // descSize, backfilled below
    data.append(contentsOf: Array("text".utf8)) // dataFormat
    appendBE32(0) // resvd1
    appendBE16(0) // resvd2
    appendBE16(1) // dataRefIndex
    appendBE32(0) // displayFlags
    appendBE32(0) // textJustification (left)
    appendBE16(0)
    appendBE16(0)
    appendBE16(0) // bgColor RGB
    appendBE16(0)
    appendBE16(0)
    appendBE16(0)
    appendBE16(0) // defaultTextBox (top,left,bottom,right)
    // defaultStyle (ScrpSTElement)
    appendBE32(0) // scrpStartChar
    appendBE16(0) // scrpHeight
    appendBE16(0) // scrpAscent
    appendBE16(0) // scrpFont
    appendBE16(0) // scrpFace
    appendBE16(12) // scrpSize
    appendBE16(0)
    appendBE16(0)
    appendBE16(0) // scrpColor RGB
    data.append(0) // textName: empty Pascal string

    let size = UInt32(data.count)
    data[0] = UInt8(size >> 24 & 0xFF)
    data[1] = UInt8(size >> 16 & 0xFF)
    data[2] = UInt8(size >> 8 & 0xFF)
    data[3] = UInt8(size & 0xFF)

    var formatDescription: CMFormatDescription?
    let created: Bool = data.withUnsafeBufferPointer { pointer in
      guard let baseAddress = pointer.baseAddress else { return false }
      return CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
        allocator: kCFAllocatorDefault,
        bigEndianTextDescriptionData: baseAddress,
        size: pointer.count,
        flavor: nil,
        mediaType: kCMMediaType_Text,
        formatDescriptionOut: &formatDescription) == noErr
    }
    return created ? formatDescription : nil
  }

  /// Build a QuickTime text sample for one chapter: a `UInt16` big-endian length prefix followed by the
  /// UTF-8 title, timed to the chapter's `[time, time + duration)` range.
  private static func makeChapterSampleBuffer(text: String, formatDescription: CMFormatDescription, time: CMTime, duration: CMTime) -> CMSampleBuffer? {
    let utf8 = Array(text.utf8.prefix(0xFFFF))
    var payload = [UInt8(utf8.count >> 8 & 0xFF), UInt8(utf8.count & 0xFF)]
    payload.append(contentsOf: utf8)

    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: payload.count,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: payload.count,
      flags: 0,
      blockBufferOut: &blockBuffer)
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
      return nil
    }
    let copied: Bool = payload.withUnsafeBytes { pointer in
      guard let baseAddress = pointer.baseAddress else { return false }
      return CMBlockBufferReplaceDataBytes(with: baseAddress, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: payload.count) == kCMBlockBufferNoErr
    }
    guard copied else {
      return nil
    }

    var sampleBuffer: CMSampleBuffer?
    var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var sampleSize = payload.count
    let sampleStatus = CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      formatDescription: formatDescription,
      sampleCount: 1,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleSizeEntryCount: 1,
      sampleSizeArray: &sampleSize,
      sampleBufferOut: &sampleBuffer)
    return sampleStatus == noErr ? sampleBuffer : nil
  }
}
