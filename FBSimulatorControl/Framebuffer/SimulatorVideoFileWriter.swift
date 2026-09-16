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

// MARK: - SimulatorVideoFileWriter

private enum SimulatorVideoFileWriterError: Error {
  case assetWriterFailedToFinish(errorDescription: String)
  case firstSampleBufferMissingFormatDescription
  case cannotAddVideoInput
  case cannotWriteChapter(String)
  case cannotWriteVideo(String)
  case assetWriterFailedToStart(errorDescription: String)
}

extension SimulatorVideoFileWriterError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .assetWriterFailedToFinish(let errorDescription):
      return "AVAssetWriter failed to finish writing: \(errorDescription)"
    case .firstSampleBufferMissingFormatDescription:
      return "First sample buffer has no format description"
    case .cannotWriteChapter(let reason):
      return "Cannot write chapter: \(reason)"
    case .cannotWriteVideo(let reason):
      return "Cannot write video: \(reason)"
    case .cannotAddVideoInput:
      return "AVAssetWriter cannot add the video input"
    case .assetWriterFailedToStart(let errorDescription):
      return "AVAssetWriter failed to start writing: \(errorDescription)"
    }
  }
}

/// Muxes encoded H.264, HEVC, or JPEG `CMSampleBuffer`s into MP4 or MOV using `AVAssetWriter` in
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
/// Chapter markers are buffered at the current video position. At finish, a second passthrough
/// writer copies the video and adds the chapter track. An empty chapter input on the live writer
/// can block video writes while waiting for chapter samples, particularly across long frame gaps.
///
/// @unchecked Sendable: `consume` runs inside the VideoToolbox output handler, whose invocations
/// alternate one frame at a time with the stream actor's encode submissions (the session is
/// configured with `MaxFrameDelayCount: 0` — see the pusher's own concurrency doc), so consumes
/// never overlap each other. `finish` is called once, from the recorder, after `stopStreaming` has
/// flushed the encoder (`VTCompressionSessionCompleteFrames`), so it never overlaps `consume`. The
/// timed-metadata path (`writeTimedMetadata`) arrives from other isolation domains (the stdin
/// handler), so the chapter state it shares with `consume`/`finish` is guarded by `chapterLock`.
final class SimulatorVideoFileWriter: EncodedSampleConsumer, TimedMetadataConsumer, @unchecked Sendable {
  private static let chapterTimeScale: CMTimeScale = 600

  private let outputURL: URL
  private let fileType: AVFileType
  private let chaptersEnabled: Bool
  private let logger: any ControlCoreLogger

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

  init(filePath: String, fileType: AVFileType = .mp4, chaptersEnabled: Bool = false, logger: any ControlCoreLogger) {
    self.outputURL = URL(fileURLWithPath: filePath)
    self.fileType = fileType
    self.chaptersEnabled = chaptersEnabled
    self.logger = logger
  }

  // MARK: - EncodedSampleConsumer

  func consume(_ sampleBuffer: CMSampleBuffer, logger: any ControlCoreLogger) -> Bool {
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

  // MARK: - TimedMetadataConsumer

  /// Buffer a chapter marker at the current video position. Written to the chapter track in `finish`.
  func writeTimedMetadata(_ text: String, logger: any ControlCoreLogger) {
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

  /// Finalize the file: mark the inputs finished and await `finishWriting`. Call once, after the
  /// encoder has flushed all pending frames. A no-op if no frame was ever written.
  func finish() async throws {
    guard let assetWriter, let input else {
      logger.log("SimulatorVideoFileWriter.finish called with no frames written; nothing to finalize")
      return
    }
    input.markAsFinished()
    await assetWriter.finishWriting()
    if assetWriter.status == .failed {
      throw SimulatorVideoFileWriterError.assetWriterFailedToFinish(errorDescription: assetWriter.error.map { String(describing: $0) } ?? "unknown error")
    }
    if chaptersEnabled && chapterLock.withLock({ !pendingChapters.isEmpty }) {
      try await addBufferedChapters()
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
      throw SimulatorVideoFileWriterError.firstSampleBufferMissingFormatDescription
    }
    // AVAssetWriter refuses to overwrite an existing file.
    try? FileManager.default.removeItem(at: outputURL)

    let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
    input.expectsMediaDataInRealTime = true
    guard assetWriter.canAdd(input) else {
      throw SimulatorVideoFileWriterError.cannotAddVideoInput
    }
    assetWriter.add(input)

    guard assetWriter.startWriting() else {
      throw SimulatorVideoFileWriterError.assetWriterFailedToStart(errorDescription: assetWriter.error.map { String(describing: $0) } ?? "unknown error")
    }
    assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    self.assetWriter = assetWriter
    self.input = input
    return input
  }

  private func addBufferedChapters() async throws {
    let temporaryURL = outputURL.appendingPathExtension("chapters-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let asset = AVURLAsset(url: outputURL)
    guard let track = try await asset.loadTracks(withMediaType: .video).first,
      let format = try await track.load(.formatDescriptions).first
    else { throw SimulatorVideoFileWriterError.cannotWriteVideo("recording has no video track") }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    let writer = try AVAssetWriter(outputURL: temporaryURL, fileType: fileType)
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
    guard writer.canAdd(videoInput) else { throw SimulatorVideoFileWriterError.cannotAddVideoInput }
    writer.add(videoInput)
    addChapterTrack(to: writer, associatedWith: videoInput)
    guard let chapterInput else { return }
    guard writer.startWriting(), reader.startReading() else {
      throw SimulatorVideoFileWriterError.cannotWriteVideo("cannot start chapter mux: \(String(describing: writer.error ?? reader.error))")
    }
    defer {
      if reader.status == .reading { reader.cancelReading() }
      if writer.status == .writing { writer.cancelWriting() }
    }
    writer.startSession(atSourceTime: .zero)
    var chapters = makeBufferedChapterSamples().makeIterator()
    var chapter = chapters.next()
    if chapter == nil { chapterInput.markAsFinished() }
    var videoFinished = false
    var progressDeadline = ContinuousClock.now + .seconds(10)
    // Feed whichever input is ready: waiting on one track alone can prevent the other from draining.
    while !videoFinished || chapter != nil {
      try Task.checkCancellation()
      var madeProgress = false
      if !videoFinished && videoInput.isReadyForMoreMediaData {
        if let sample = output.copyNextSampleBuffer() {
          if CMSampleBufferGetNumSamples(sample) > 0, !videoInput.append(sample) {
            throw SimulatorVideoFileWriterError.cannotWriteVideo(String(describing: writer.error))
          }
        } else {
          guard reader.status == .completed else {
            throw SimulatorVideoFileWriterError.cannotWriteVideo(String(describing: reader.error))
          }
          videoInput.markAsFinished()
          videoFinished = true
        }
        madeProgress = true
      }
      if let sample = chapter, chapterInput.isReadyForMoreMediaData {
        guard chapterInput.append(sample) else {
          throw SimulatorVideoFileWriterError.cannotWriteChapter(String(describing: writer.error))
        }
        chapter = chapters.next()
        if chapter == nil { chapterInput.markAsFinished() }
        madeProgress = true
      }
      if madeProgress {
        progressDeadline = ContinuousClock.now + .seconds(10)
      } else {
        guard writer.status == .writing, ContinuousClock.now < progressDeadline else {
          throw SimulatorVideoFileWriterError.cannotWriteVideo("chapter mux stopped making progress: \(String(describing: writer.error))")
        }
        try await Task.sleep(for: .milliseconds(1))
      }
    }
    await writer.finishWriting()
    guard writer.status == .completed else {
      throw SimulatorVideoFileWriterError.assetWriterFailedToFinish(errorDescription: String(describing: writer.error))
    }
    _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryURL)
  }

  private func addChapterTrack(to assetWriter: AVAssetWriter, associatedWith videoInput: AVAssetWriterInput) {
    guard let formatDescription = Self.makeChapterTextFormatDescription() else {
      logger.log("Failed to build chapter text format description; recording without chapters")
      return
    }
    let chapterInput = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: formatDescription)
    chapterInput.expectsMediaDataInRealTime = false
    // Chapter durations use 32-bit ticks; nanosecond precision overflows after 4.3 seconds.
    chapterInput.mediaTimeScale = Self.chapterTimeScale
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

  /// Convert buffered markers to text samples with contiguous time ranges:
  /// each chapter runs until the next one, and the last until the end of the recorded video.
  private func makeBufferedChapterSamples() -> [CMSampleBuffer] {
    let (chapters, sessionStart, videoEnd) = chapterLock.withLock {
      (pendingChapters, firstPresentationTime, lastPresentationTime)
    }

    guard let formatDescription = chapterFormatDescription, !chapters.isEmpty else {
      return []
    }
    var resolved: [(time: CMTime, text: String)] = []
    for chapter in chapters {
      let relativeTime = chapter.time.isValid ? CMTimeSubtract(chapter.time, sessionStart) : .zero
      let time = CMTimeConvertScale(relativeTime, timescale: Self.chapterTimeScale, method: .roundHalfAwayFromZero)
      // QuickTime text samples cannot overlap. Updates within one video frame keep the latest title.
      if resolved.last?.time == time {
        resolved[resolved.count - 1] = (time, chapter.text)
      } else {
        resolved.append((time, chapter.text))
      }
    }
    let minDuration = CMTimeMake(value: 1, timescale: Self.chapterTimeScale)
    let end = CMTimeConvertScale(CMTimeSubtract(videoEnd, sessionStart), timescale: Self.chapterTimeScale, method: .roundHalfAwayFromZero)
    var samples: [CMSampleBuffer] = []
    for (index, chapter) in resolved.enumerated() {
      let start = chapter.time
      let rawEnd = index + 1 < resolved.count ? resolved[index + 1].time : end
      var duration = CMTimeSubtract(rawEnd, start)
      if !duration.isValid || duration <= .zero {
        duration = minDuration
      }
      guard let sample = Self.makeChapterSampleBuffer(text: chapter.text, formatDescription: formatDescription, time: start, duration: duration) else {
        logger.log("Failed to build chapter sample for '\(chapter.text)', skipping")
        continue
      }
      samples.append(sample)
    }
    return samples
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
