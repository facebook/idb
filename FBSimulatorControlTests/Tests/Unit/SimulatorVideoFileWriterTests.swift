/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class SimulatorVideoFileWriterTests: XCTestCase {

  func testWritesReadablePassthroughVideoTrack() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatorVideoFileWriterTests-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let logger = CapturingLogger()
    let writer = SimulatorVideoFileWriter(filePath: path, logger: logger)

    let frameCount = 10
    for index in 0..<frameCount {
      XCTAssertTrue(writer.consume(sampleBuffer(frameIndex: index), logger: logger), "frame \(index) should append")
    }
    try await writer.finish()

    XCTAssertTrue(FileManager.default.fileExists(atPath: path), "output file should exist")

    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let tracks = try await asset.loadTracks(withMediaType: .video)
    XCTAssertEqual(tracks.count, 1, "should have exactly one video track")
    let duration = try await asset.load(.duration)
    XCTAssertGreaterThan(CMTimeGetSeconds(duration), 0, "duration should be non-zero")

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: nil)
    reader.add(output)
    XCTAssertTrue(reader.startReading(), "reader should start")
    var readSamples = 0
    while let sample = output.copyNextSampleBuffer() {
      if CMSampleBufferGetNumSamples(sample) > 0 {
        readSamples += 1
      }
    }
    XCTAssertEqual(reader.status, .completed, "reader should complete without error")
    XCTAssertEqual(readSamples, frameCount, "every appended frame should be readable back")
  }

  func testRecordingIsReadableBeforeFinishSoAnInterruptedRunKeepsItsFrames() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatorVideoFileWriterTests-fragmented-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let logger = CapturingLogger()
    let writer = SimulatorVideoFileWriter(filePath: path, logger: logger)

    // A frame a second, so a few frames span several fragment intervals.
    let frameCount = 20
    for index in 0..<frameCount {
      let sample = sampleBuffer(frameIndex: index, timestamp: CMTimeMake(value: Int64(index), timescale: 1))
      XCTAssertTrue(writer.consume(sample, logger: logger), "frame \(index) should append")
    }

    // `finish` is deliberately not called: this is the state a recording is left in when the writer
    // never reaches finalization. Written as one un-fragmented movie the file would carry no index
    // at all here and could not be opened, losing every frame above.
    //
    // Read samples back rather than just loading the track list. A fragmented movie publishes its
    // tracks in the initial `moov`, so a track would be discoverable even with no usable fragment
    // behind it; the property worth asserting is that frames actually come back.
    let minimumRecoveredSamples = 10
    let deadline = Date().addingTimeInterval(30)
    var recoveredSamples = 0
    while recoveredSamples < minimumRecoveredSamples && Date() < deadline {
      recoveredSamples = (try? await Self.readableSampleCount(atPath: path)) ?? 0
      if recoveredSamples < minimumRecoveredSamples {
        try await Task.sleep(nanoseconds: 200_000_000)
      }
    }
    // Only whole fragments are recoverable, so the frames written since the last flush are expected
    // to be missing. The claim is that an interrupted recording keeps most of itself, not all.
    XCTAssertGreaterThanOrEqual(
      recoveredSamples,
      minimumRecoveredSamples,
      "an unfinished recording should hand back the frames in its completed fragments; logs=\(logger.messages)")
    XCTAssertLessThanOrEqual(recoveredSamples, frameCount, "cannot recover more frames than were appended")

    // Finalizing still produces a complete, readable movie.
    try await writer.finish()
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let finishedTracks = try await asset.loadTracks(withMediaType: .video)
    XCTAssertEqual(finishedTracks.count, 1, "finished recording should have exactly one video track")
    let duration = try await asset.load(.duration)
    XCTAssertGreaterThan(CMTimeGetSeconds(duration), 0, "duration should be non-zero")
  }

  /// Frames the movie at `path` can hand back right now, read the way any consumer would. Zero
  /// covers both "no track yet" and "a track with nothing readable behind it".
  fileprivate static func readableSampleCount(atPath path: String) async throws -> Int {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      return 0
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    guard reader.startReading() else {
      return 0
    }
    defer {
      if reader.status == .reading {
        reader.cancelReading()
      }
    }
    var samples = 0
    while let sample = output.copyNextSampleBuffer() {
      if CMSampleBufferGetNumSamples(sample) > 0 {
        samples += 1
      }
    }
    return samples
  }

  func testWritesReadableChapterTrack() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatorVideoFileWriterTests-chapters-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let logger = CapturingLogger()
    let writer = SimulatorVideoFileWriter(filePath: path, chaptersEnabled: true, logger: logger)

    let chaptersByFrame = [0: "Intro", 10: "Middle", 20: "End"]
    for index in 0..<30 {
      XCTAssertTrue(writer.consume(sampleBuffer(frameIndex: index), logger: logger), "frame \(index) should append")
      if let title = chaptersByFrame[index] {
        writer.writeTimedMetadata(title, logger: logger)
      }
    }
    try await writer.finish()

    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    XCTAssertEqual(videoTracks.count, 1, "video track should survive")
    let textTracks = try await asset.loadTracks(withMediaType: .text)
    XCTAssertEqual(textTracks.count, 1, "chapter text track should exist; logs=\(logger.messages)")

    // Read the chapter text samples back directly (each is a UInt16-length-prefixed UTF-8 title),
    // which verifies the written content independently of AVFoundation's language-filtered reader.
    let titles = try Self.readChapterTitles(track: textTracks[0], asset: asset)
    XCTAssertEqual(titles, ["Intro", "Middle", "End"], "chapter titles should round-trip in order")

    // The text track is wired as a chapter list, so AVFoundation surfaces it as chapter metadata.
    let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: ["und"])
    XCTAssertEqual(groups.count, 3, "should expose three chapter groups")
  }

  /// Reads a text track's samples and decodes each QuickTime text sample (UInt16 big-endian length
  /// prefix + UTF-8) back into its title string.
  fileprivate static func readChapterTitles(track: AVAssetTrack, asset: AVAsset) throws -> [String] {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    XCTAssertTrue(reader.startReading(), "chapter reader should start")
    var titles: [String] = []
    while let sample = output.copyNextSampleBuffer() {
      guard let blockBuffer = CMSampleBufferGetDataBuffer(sample) else { continue }
      var length = 0
      var dataPointer: UnsafeMutablePointer<CChar>?
      guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
        let dataPointer, length >= 2
      else { continue }
      dataPointer.withMemoryRebound(to: UInt8.self, capacity: length) { bytes in
        let textLength = Int(bytes[0]) << 8 | Int(bytes[1])
        if length >= 2 + textLength {
          let data = Data(bytes: bytes + 2, count: textLength)
          if let title = String(data: data, encoding: .utf8) {
            titles.append(title)
          }
        }
      }
    }
    XCTAssertEqual(reader.status, .completed, "chapter reader should complete")
    return titles
  }

  func testNoChapterTrackWhenDisabled() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatorVideoFileWriterTests-nochapters-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let logger = CapturingLogger()
    let writer = SimulatorVideoFileWriter(filePath: path, logger: logger)
    for index in 0..<10 {
      XCTAssertTrue(writer.consume(sampleBuffer(frameIndex: index), logger: logger))
      writer.writeTimedMetadata("ignored \(index)", logger: logger)
    }
    try await writer.finish()

    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: ["en"])
    XCTAssertTrue(groups.isEmpty, "no chapters should be present when disabled")
    let textTracks = try await asset.loadTracks(withMediaType: .text)
    XCTAssertTrue(textTracks.isEmpty, "no text track should be added when disabled")
  }

  func testChapterMarkersAtTheSameFrame() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("chapters-same-frame-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let logger = CapturingLogger()
    let writer = SimulatorVideoFileWriter(filePath: path, fileType: .mov, chaptersEnabled: true, logger: logger)
    XCTAssertTrue(writer.consume(sampleBuffer(frameIndex: 0), logger: logger))
    writer.writeTimedMetadata("First", logger: logger)
    writer.writeTimedMetadata("Second", logger: logger)
    for index in 1..<30 {
      XCTAssertTrue(writer.consume(sampleBuffer(frameIndex: index), logger: logger))
    }
    try await writer.finish()
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let tracks = try await asset.loadTracks(withMediaType: .text)
    let track = try XCTUnwrap(tracks.first)
    XCTAssertEqual(try Self.readChapterTitles(track: track, asset: asset), ["Second"])
  }

  func testManyChaptersAcrossALongTimeline() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("chapters-long-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let logger = CapturingLogger()
    let writer = SimulatorVideoFileWriter(filePath: path, fileType: .mov, chaptersEnabled: true, logger: logger)
    let titles = (0..<30).map { "Chapter \($0)" }
    for index in 0..<30 {
      XCTAssertTrue(writer.consume(sampleBuffer(frameIndex: index * 300), logger: logger))
      writer.writeTimedMetadata(titles[index], logger: logger)
    }
    XCTAssertTrue(writer.consume(sampleBuffer(frameIndex: 9000), logger: logger))
    try await writer.finish()
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let tracks = try await asset.loadTracks(withMediaType: .text)
    let track = try XCTUnwrap(tracks.first)
    XCTAssertEqual(try Self.readChapterTitles(track: track, asset: asset), titles)
  }

  func testFinishWithoutFramesDoesNotThrow() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatorVideoFileWriterTests-empty-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let writer = SimulatorVideoFileWriter(filePath: path, logger: CapturingLogger())
    try await writer.finish()
  }

  func testLongChaptersAtTheEncoderTimeScale() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("chapters-nanoseconds-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let logger = CapturingLogger()
    let writer = SimulatorVideoFileWriter(filePath: path, fileType: .mov, chaptersEnabled: true, logger: logger)
    for index in 0..<18 {
      let timestamp = CMTime(value: Int64(index) * 1_000_000_000 + 123_456, timescale: 1_000_000_000)
      XCTAssertTrue(writer.consume(sampleBuffer(frameIndex: index, timestamp: timestamp), logger: logger))
      if index % 6 == 0 { writer.writeTimedMetadata("Chapter \(index / 6)", logger: logger) }
    }
    try await writer.finish()
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let tracks = try await asset.loadTracks(withMediaType: .text)
    let track = try XCTUnwrap(tracks.first)
    XCTAssertEqual(try Self.readChapterTitles(track: track, asset: asset), ["Chapter 0", "Chapter 1", "Chapter 2"])
    let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: ["und"])
    XCTAssertEqual(groups.count, 3)
    for (index, group) in groups.enumerated() {
      XCTAssertEqual(group.timeRange.start.seconds, Double(index * 6), accuracy: 0.002)
    }
  }

  func testWritingAfterLongFrameGaps() async throws {
    for chaptersEnabled in [false, true] {
      let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("video-gaps-\(UUID().uuidString).mov")
      defer { try? FileManager.default.removeItem(atPath: path) }
      let logger = CapturingLogger()
      let writer = SimulatorVideoFileWriter(filePath: path, fileType: .mov, chaptersEnabled: chaptersEnabled, logger: logger)
      writer.writeTimedMetadata("Long frame gaps", logger: logger)
      var previous = 0.0
      let timestamps = [0.0, 0.1, 0.2, 5.2, 5.3, 5.4, 30.4, 30.5, 30.6] + (1...200).map { 30.6 + Double($0) / 1000 }
      for (index, timestamp) in timestamps.enumerated() {
        var timing = CMSampleTimingInfo(
          duration: index == 0 ? .invalid : CMTimeMakeWithSeconds(timestamp - previous, preferredTimescale: 1_000_000_000),
          presentationTimeStamp: CMTimeMakeWithSeconds(timestamp, preferredTimescale: 1_000_000_000),
          decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: createH264SampleBuffer(), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &sample), noErr)
        let encoded = try XCTUnwrap(sample)
        let deadline = ContinuousClock.now + .seconds(2)
        var appended = writer.consume(encoded, logger: logger)
        while !appended && ContinuousClock.now < deadline {
          try await Task.sleep(for: .milliseconds(1))
          appended = writer.consume(encoded, logger: logger)
        }
        guard appended else {
          XCTFail("chapters=\(chaptersEnabled), frame=\(index), logs=\(logger.messages.suffix(5))")
          _ = try? await writer.finish()
          return
        }
        previous = timestamp
      }
      try await writer.finish()
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      let duration = try await asset.load(.duration)
      XCTAssertGreaterThan(duration.seconds, 30.7)
      let videoTracks = try await asset.loadTracks(withMediaType: .video)
      let reader = try AVAssetReader(asset: asset)
      let output = AVAssetReaderTrackOutput(track: try XCTUnwrap(videoTracks.first), outputSettings: nil)
      reader.add(output)
      XCTAssertTrue(reader.startReading())
      var frames = 0
      while let sample = output.copyNextSampleBuffer() {
        if CMSampleBufferGetNumSamples(sample) > 0 { frames += 1 }
      }
      XCTAssertEqual(reader.status, .completed)
      XCTAssertEqual(frames, timestamps.count)
      let chapters = try await asset.loadTracks(withMediaType: .text)
      if chaptersEnabled {
        XCTAssertEqual(try Self.readChapterTitles(track: XCTUnwrap(chapters.first), asset: asset), ["Long frame gaps"])
      } else {
        XCTAssertTrue(chapters.isEmpty)
      }
    }
  }

  // MARK: - Helpers

  /// A copy of the shared synthetic H264 sample with its presentation timestamp set to `frameIndex`
  /// at 30fps, so a sequence forms a monotonic timeline the muxer can build a real duration from.
  private func sampleBuffer(frameIndex: Int, timestamp: CMTime? = nil) -> CMSampleBuffer {
    let base = createH264SampleBuffer()
    var timing = CMSampleTimingInfo(
      duration: CMTimeMake(value: 1, timescale: 30),
      presentationTimeStamp: timestamp ?? CMTimeMake(value: Int64(frameIndex), timescale: 30),
      decodeTimeStamp: .invalid)
    var copy: CMSampleBuffer?
    let status = CMSampleBufferCreateCopyWithNewTiming(
      allocator: nil,
      sampleBuffer: base,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleBufferOut: &copy)
    precondition(status == noErr, "Failed to copy sample buffer timing: \(status)")
    return copy!
  }
}

/// Lifecycle tests for `SimulatorVideo`, the in-process recorder wrapping the stream + file
/// writer, driven end-to-end over a fake display surface with a real VideoToolbox encode.
final class SimulatorVideoTests: XCTestCase {

  /// A recorder over a fake display surface writing to a temp path removed at teardown. The eager
  /// cadence (positive framesPerSecond) pushes frames on the clock from the mounted surface without
  /// needing frame-rendered events from the fake.
  private func makeRecordingFixture(immediateSurface: IOSurface?, format: VideoStreamFormat = .compressedVideo(withCodec: .h264, transport: .fmp4), fileType: AVFileType = .mp4, chaptersEnabled: Bool = false) -> (video: SimulatorVideo, path: String) {
    let extensionName = fileType == .mov ? "mov" : "mp4"
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatorVideoTests-\(UUID().uuidString).\(extensionName)")
    addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = immediateSurface
    let framebuffer = Framebuffer(surface: surface, logger: CapturingLogger())
    let configuration = VideoStreamConfiguration(
      format: format,
      framesPerSecond: 30,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil)
    let video = SimulatorVideo.video(withFramebuffer: framebuffer, configuration: configuration, filePath: path, fileType: fileType, chaptersEnabled: chaptersEnabled, logger: CapturingLogger())
    return (video, path)
  }

  /// The writer creates the output file when the encoder emits its first sample, so its existence
  /// marks the first sample.
  private func waitForFirstSample(at path: String, timeout: TimeInterval = 10) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if FileManager.default.fileExists(atPath: path) {
        return
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTFail("the recording never produced its first sample at \(path)")
  }

  func testRecordingProducesReadableMp4() async throws {
    try VideoEncodingHostSupport.skipUnlessHardwareH264Encoding()
    let (video, path) = makeRecordingFixture(immediateSurface: makeTestIOSurface(width: 128, height: 128))

    try await video.startRecording()
    try await waitForFirstSample(at: path)
    let url = try await video.stop()

    XCTAssertEqual(url.path, path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: path), "recording must finalize a file")
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    XCTAssertEqual(tracks.count, 1, "recording must contain one video track")
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: nil)
    reader.add(output)
    XCTAssertTrue(reader.startReading())
    var readSamples = 0
    while let sample = output.copyNextSampleBuffer() {
      if CMSampleBufferGetNumSamples(sample) > 0 {
        readSamples += 1
      }
    }
    XCTAssertEqual(reader.status, .completed)
    XCTAssertGreaterThan(readSamples, 0, "recorded frames must be readable back")
  }

  func testJPEGRecordingHasDecodableFramesAndChapters() async throws {
    let (video, _) = makeRecordingFixture(
      immediateSurface: makeTestIOSurface(width: 128, height: 128),
      format: .mjpeg(encoder: .allowSoftware), fileType: .mov, chaptersEnabled: true)
    addTeardownBlock { _ = try? await video.stop() }
    try await video.startRecording()
    await video.stream.writeTimedMetadata("First")
    let deadline = ContinuousClock.now + .seconds(10)
    while await video.stream.currentEncoderStats().writeCount < 3 {
      guard ContinuousClock.now < deadline else {
        return XCTFail("JPEG recording produced no usable frames")
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    await video.stream.writeTimedMetadata("Second")
    try await Task.sleep(for: .milliseconds(200))
    let asset = AVURLAsset(url: try await video.stop())
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first)
    let formats = try await track.load(.formatDescriptions)
    XCTAssertEqual(CMFormatDescriptionGetMediaSubType(try XCTUnwrap(formats.first)), kCMVideoCodecType_JPEG)
    let size = try await track.load(.naturalSize)
    XCTAssertEqual(size, CGSize(width: 128, height: 128))
    let duration = try await asset.load(.duration)
    XCTAssertGreaterThan(duration.seconds, 0)

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    XCTAssertTrue(reader.startReading())
    var decodedFrames = 0
    while let sample = output.copyNextSampleBuffer() {
      XCTAssertNotNil(CMSampleBufferGetImageBuffer(sample))
      decodedFrames += 1
    }
    XCTAssertEqual(reader.status, .completed)
    XCTAssertGreaterThanOrEqual(decodedFrames, 3)
    let chapterTracks = try await asset.loadTracks(withMediaType: .text)
    let chapterTrack = try XCTUnwrap(chapterTracks.first)
    XCTAssertEqual(try SimulatorVideoFileWriterTests.readChapterTitles(track: chapterTrack, asset: asset), ["First", "Second"])
  }

  func testSecondStopReturnsSameURLWithoutRefinalizing() async throws {
    try VideoEncodingHostSupport.skipUnlessHardwareH264Encoding()
    let (video, path) = makeRecordingFixture(immediateSurface: makeTestIOSurface(width: 128, height: 128))

    try await video.startRecording()
    try await waitForFirstSample(at: path)
    let first = try await video.stop()
    let second = try await video.stop()

    XCTAssertEqual(first, second, "a second stop returns the same URL without re-finalizing")
  }

  func testStopBeforeStartThrowsAndLatchesStopped() async throws {
    let (video, path) = makeRecordingFixture(immediateSurface: nil)

    do {
      _ = try await video.stop()
      XCTFail("stop before start must throw")
      return
    } catch {
      XCTAssertTrue(String(describing: error).contains("stopWithoutConsumer"), "unexpected error: \(error)")
    }
    let url = try await video.stop()
    XCTAssertEqual(url.path, path)
  }
}
