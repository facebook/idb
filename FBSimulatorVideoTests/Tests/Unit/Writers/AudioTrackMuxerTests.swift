/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import FBControlCore
@testable import FBSimulatorVideo
import FBVideoCore
import Foundation
import Testing

private let sampleRate = 48_000.0

@Suite("Audio track muxer")
final class AudioTrackMuxerTests {
  private let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AudioTrackMuxerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  @Test func audioThatStartsAfterTheVideoStartsWhereItsOffsetPutsIt() async throws {
    let video = try await recording(frames: 30)
    let audio = try wav(silence: 0, tone: 0.5)

    let placement = try await AudioTrackMuxer.addAudio(
      fromWAV: audio, offset: 0.25, to: video, fileType: .mp4, logger: CapturingLogger())

    #expect(placement.offset == 0.25)
    #expect(placement.frames == 24_000)
    // The track plays silence until a quarter second in, then the tone, at its level to well within
    // a decibel after AAC.
    let decoded = try await decodedAudio(video)
    #expect(decoded.start == 0)
    #expect(rms(decoded.left[0..<11_500]) < 0.001)
    #expect(abs(rms(decoded.left[12_500..<24_000]) - 0.5 / 2.0.squareRoot()) < 0.02)
    let onset = try #require(decoded.left.firstIndex { abs($0) > 0.2 })
    #expect(abs(onset - 12_003) <= 48, "the tone should start within a millisecond of 0.25 s, not at frame \(onset)")
    #expect(try await videoFrames(video) == 30)
  }

  @Test func audioFromBeforeTheVideoIsCut() async throws {
    let video = try await recording(frames: 30)
    // A quarter second of silence before the video started, then the tone.
    let audio = try wav(silence: 0.25, tone: 0.5)

    let placement = try await AudioTrackMuxer.addAudio(
      fromWAV: audio, offset: -0.25, to: video, fileType: .mp4, logger: CapturingLogger())

    #expect(placement.frames == 24_000)
    let decoded = try await decodedAudio(video)
    #expect(abs(decoded.start) < 0.001)
    // The silence was cut, so the tone plays from the start.
    #expect(rms(decoded.left[480..<4_800]) > 0.3)
  }

  @Test(arguments: ["webm", "bin"])
  func aRecordingIsReadAsItsFileTypeWhateverItsName(filenameExtension: String) async throws {
    // A client may name the file after a format it converts to later; the companion writes MP4.
    let recorded = try await recording(frames: 30)
    let video = recorded.deletingPathExtension().appendingPathExtension(filenameExtension)
    try FileManager.default.moveItem(at: recorded, to: video)
    let audio = try wav(silence: 0, tone: 0.5)

    let placement = try await AudioTrackMuxer.addAudio(
      fromWAV: audio, offset: 0, to: video, fileType: .mp4, logger: CapturingLogger())

    #expect(placement.frames == 24_000)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
      $0.hasPrefix(video.lastPathComponent + ".video-")
    }
    #expect(leftovers.isEmpty)
    let readable = video.deletingPathExtension().appendingPathExtension("mp4")
    try FileManager.default.moveItem(at: video, to: readable)
    #expect(try await videoFrames(readable) == 30)
    #expect(rms(try await decodedAudio(readable).left[4_800..<20_000]) > 0.3)
  }

  @Test func aRecordingThatHoldsMoreThanVideoIsRefused() async throws {
    let video = try await recording(frames: 30)
    let audio = try wav(silence: 0, tone: 0.1)
    _ = try await AudioTrackMuxer.addAudio(fromWAV: audio, offset: 0, to: video, fileType: .mp4, logger: CapturingLogger())

    await #expect {
      _ = try await AudioTrackMuxer.addAudio(fromWAV: audio, offset: 0, to: video, fileType: .mp4, logger: CapturingLogger())
    } throws: { error in
      guard case .unsupportedRecording = error as? AudioTrackMuxerError else {
        return false
      }
      return true
    }
  }

  @Test func aFileWithoutAudioIsRefusedAndTheRecordingKept() async throws {
    let video = try await recording(frames: 30)
    let notAudio = directory.appendingPathComponent("not-audio.wav")
    try Data("not audio".utf8).write(to: notAudio)

    await #expect {
      _ = try await AudioTrackMuxer.addAudio(
        fromWAV: notAudio, offset: 0, to: video, fileType: .mp4, logger: CapturingLogger())
    } throws: { error in
      guard case .unreadableAudio = error as? AudioTrackMuxerError else {
        return false
      }
      return true
    }
    #expect(try await videoFrames(video) == 30)
  }

  @Test(arguments: [0.0, 3_000_000_000.0])
  func audioAtARateNoRecordingCanBeTimedInIsRefusedAndTheRecordingKept(reportedRate: Double) async throws {
    let video = try await recording(frames: 30)
    let audio = try wav(silence: 0, tone: 0.25, reportedRate: reportedRate)

    await #expect {
      _ = try await AudioTrackMuxer.addAudio(fromWAV: audio, offset: 0, to: video, fileType: .mp4, logger: CapturingLogger())
    } throws: { error in
      guard case .unreadableAudio = error as? AudioTrackMuxerError else {
        return false
      }
      return true
    }
    #expect(try await videoFrames(video) == 30)
  }

  // MARK: - Fixtures

  /// A recording of video alone, from the shared synthetic H.264 sample at 30 frames a second.
  private func recording(frames: Int) async throws -> URL {
    let url = directory.appendingPathComponent("video-\(UUID().uuidString).mp4")
    let logger = CapturingLogger()
    let writer = SimulatorVideoFileWriter(filePath: url.path, logger: logger)
    for index in 0..<frames {
      var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: Int64(index), timescale: 30),
        decodeTimeStamp: .invalid)
      var sample: CMSampleBuffer?
      CMSampleBufferCreateCopyWithNewTiming(
        allocator: nil, sampleBuffer: createH264SampleBuffer(), sampleTimingEntryCount: 1, sampleTimingArray: &timing,
        sampleBufferOut: &sample)
      #expect(writer.consume(try #require(sample), logger: logger))
    }
    try await writer.finish()
    return url
  }

  /// A two-channel, 32-bit float WAV, the kind a capture is mixed into: `silence` seconds of silence,
  /// then `tone` seconds of a 1 kHz sine at half of full scale. Its header reports `reportedRate`.
  private func wav(silence: Double, tone: Double, reportedRate: Double? = nil) throws -> URL {
    let silent = Int(silence * sampleRate)
    let toned = Int(tone * sampleRate)
    var samples: [Float] = Array(repeating: 0, count: silent * 2)
    for frame in 0..<toned {
      let value = Float(0.5 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate))
      samples += [value, value]
    }
    var data = Data()
    func append<Value: FixedWidthInteger>(_ value: Value) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let dataBytes = samples.count * 4
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + dataBytes))
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(3))
    append(UInt16(2))
    append(UInt32(reportedRate ?? sampleRate))
    append(UInt32(clamping: UInt64((reportedRate ?? sampleRate) * 8)))
    append(UInt16(8))
    append(UInt16(32))
    data.append(contentsOf: Array("data".utf8))
    append(UInt32(dataBytes))
    samples.withUnsafeBytes { data.append(contentsOf: $0) }
    let url = directory.appendingPathComponent("audio-\(UUID().uuidString).wav")
    try data.write(to: url)
    return url
  }

  /// When the recording's audio track starts, and its left channel decoded.
  private func decodedAudio(_ url: URL) async throws -> (start: Double, left: [Float]) {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
      ])
    reader.add(output)
    #expect(reader.startReading())
    var start: Double?
    var left: [Float] = []
    while let sample = output.copyNextSampleBuffer() {
      start = start ?? CMSampleBufferGetPresentationTimeStamp(sample).seconds
      guard let block = CMSampleBufferGetDataBuffer(sample) else {
        continue
      }
      var length = 0
      var pointer: UnsafeMutablePointer<CChar>?
      CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
      guard let pointer else {
        continue
      }
      let floats = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: length / 4)
      left += stride(from: 0, to: length / 4, by: 2).map { floats[$0] }
    }
    #expect(reader.status == .completed)
    return (try #require(start), left)
  }

  private func videoFrames(_ url: URL) async throws -> Int {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    #expect(reader.startReading())
    var frames = 0
    while let sample = output.copyNextSampleBuffer() {
      frames += CMSampleBufferGetNumSamples(sample)
    }
    return frames
  }

  private func rms(_ samples: ArraySlice<Float>) -> Double {
    (samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
  }
}
