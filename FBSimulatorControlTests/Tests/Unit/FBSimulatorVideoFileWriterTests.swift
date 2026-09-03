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

final class FBSimulatorVideoFileWriterTests: XCTestCase {

  /// Feeds encoded H264 samples through the writer, finalizes, then reopens the file to confirm it is
  /// a valid mp4 with one video track, a non-zero duration, and every appended frame readable back.
  func testWritesReadablePassthroughVideoTrack() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorVideoFileWriterTests-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let logger = FBCapturingLogger()
    let writer = FBSimulatorVideoFileWriter(filePath: path, logger: logger)

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

  /// With chapters enabled, markers fed mid-recording become a player-visible QuickTime chapter track
  /// whose titles and order survive a finalize + reopen.
  func testWritesReadableChapterTrack() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorVideoFileWriterTests-chapters-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let logger = FBCapturingLogger()
    let writer = FBSimulatorVideoFileWriter(filePath: path, chaptersEnabled: true, logger: logger)

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
  private static func readChapterTitles(track: AVAssetTrack, asset: AVAsset) throws -> [String] {
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

  /// Without chapters enabled, markers are dropped and no chapter track is added — the default
  /// recording output is unchanged.
  func testNoChapterTrackWhenDisabled() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorVideoFileWriterTests-nochapters-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let logger = FBCapturingLogger()
    let writer = FBSimulatorVideoFileWriter(filePath: path, logger: logger)
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

  /// Finalizing a writer that never received a frame is a no-op rather than an error.
  func testFinishWithoutFramesDoesNotThrow() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorVideoFileWriterTests-empty-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let writer = FBSimulatorVideoFileWriter(filePath: path, logger: FBCapturingLogger())
    try await writer.finish()
  }

  // MARK: - Helpers

  /// A copy of the shared synthetic H264 sample with its presentation timestamp set to `frameIndex`
  /// at 30fps, so a sequence forms a monotonic timeline the muxer can build a real duration from.
  private func sampleBuffer(frameIndex: Int) -> CMSampleBuffer {
    let base = createH264SampleBuffer()
    var timing = CMSampleTimingInfo(
      duration: CMTimeMake(value: 1, timescale: 30),
      presentationTimeStamp: CMTimeMake(value: Int64(frameIndex), timescale: 30),
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

/// Lifecycle tests for `FBSimulatorVideo`, the in-process recorder wrapping the stream + file
/// writer, driven end-to-end over a fake display surface with a real VideoToolbox encode.
final class FBSimulatorVideoTests: XCTestCase {

  /// A recorder over a fake display surface writing to a temp path removed at teardown. The eager
  /// cadence (positive framesPerSecond) pushes frames on the clock from the mounted surface without
  /// needing frame-rendered events from the fake.
  private func makeRecordingFixture(immediateSurface: IOSurface?) -> (video: FBSimulatorVideo, path: String) {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorVideoTests-\(UUID().uuidString).mp4")
    addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = immediateSurface
    let framebuffer = FBFramebuffer(surface: surface, logger: FBCapturingLogger())
    let configuration = FBVideoStreamConfiguration(
      format: .compressedVideo(withCodec: .h264, transport: .fmp4),
      framesPerSecond: 30,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil)
    let video = FBSimulatorVideo.video(withFramebuffer: framebuffer, configuration: configuration, filePath: path, logger: FBCapturingLogger())
    return (video, path)
  }

  /// Wait until the recording's output file exists — the writer creates it when the encoder emits
  /// its first sample — rather than sleeping a fixed interval, which flakes on loaded machines.
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
    // Hardware video encoding is unavailable on hosted CI runners: the encoder
    // never produces output, so the assertions cannot be exercised there.
    try XCTSkipIf(
      ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      "video encoding is not available on hosted CI runners")
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

  func testSecondStopReturnsSameURLWithoutRefinalizing() async throws {
    // Hardware video encoding is unavailable on hosted CI runners: the encoder
    // never produces output, so the assertions cannot be exercised there.
    try XCTSkipIf(
      ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      "video encoding is not available on hosted CI runners")
    let (video, path) = makeRecordingFixture(immediateSurface: makeTestIOSurface(width: 128, height: 128))

    try await video.startRecording()
    try await waitForFirstSample(at: path)
    let first = try await video.stop()
    let second = try await video.stop()

    XCTAssertEqual(first, second, "a second stop returns the same URL without re-finalizing")
  }

  func testStopBeforeStartThrowsAndLatchesStopped() async throws {
    let (video, path) = makeRecordingFixture(immediateSurface: nil)

    // Stopping a recording that never started throws (there is no stream to stop), and latches the
    // stopped flag so a subsequent stop reports the output URL without touching the stream again.
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
