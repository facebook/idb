/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
@testable import FBSimulatorControl
import XCTest

final class FBVideoFileWriterTests: XCTestCase {

  /// Feeds encoded H264 samples through the writer, finalizes, then reopens the file to confirm it is
  /// a valid mp4 with one video track, a non-zero duration, and every appended frame readable back.
  func testWritesReadablePassthroughVideoTrack() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBVideoFileWriterTests-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let logger = FBCapturingLogger()
    let writer = FBVideoFileWriter(filePath: path, logger: logger)

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

  /// Finalizing a writer that never received a frame is a no-op rather than an error.
  func testFinishWithoutFramesDoesNotThrow() async throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBVideoFileWriterTests-empty-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let writer = FBVideoFileWriter(filePath: path, logger: FBCapturingLogger())
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
