/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import FBControlCore
import FBSimulatorCodeInjection
import FBSimulatorControl
import FBSimulatorVideo
import FBVideoCore
import XCTest

/// Records an app's screen and sound together through the libraries' public API, as a consumer
/// outside idb would, and checks that the recording holds what the app played: at its level, and in
/// step with what it showed. Settings, a system app, hosts a payload that flashes the screen green
/// and clicks at the same moment.
final class AudioCaptureSmokeTests: ProvidedSimulatorTestCase {

  private static let bundleID = "com.apple.Preferences"
  /// What the payload plays: eight clicks, half a second apart, each peaking at half of full scale.
  private static let flashCount = 8
  private static let clickPeak: Float = 0.5
  /// How far the sound may lead or trail the picture. A viewer notices sound leading by more than
  /// 45 ms; a frame of this recording is 17 ms.
  private static let syncTolerance = 0.045
  /// How far one flash's offset may stray from the others'.
  private static let jitterTolerance = 0.025

  private var directory: URL!

  override func setUp() async throws {
    try await super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AudioCaptureSmokeTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let simulator = self.simulator!
    let directory = self.directory!
    addTeardownBlock {
      try? await simulator.application.kill(bundleID: Self.bundleID)
      try? FileManager.default.removeItem(at: directory)
    }
  }

  func testARecordingHoldsWhatTheAppPlaysInStepWithWhatItShows() async throws {
    let payload = try XCTUnwrap(BundledResources.path(forItem: "libCodeInjectionPayload-iOS.dylib"), "The payload is a resource of this bundle")
    // Launched as idb launches an app, so the shim keeps what it plays, and code can be injected.
    let environment = await simulator.audioInjection.appLaunchEnvironment(
      try simulator.codeInjection.launchEnvironment(forApplication: Self.bundleID))
    _ = try await simulator.application.launch(
      ApplicationLaunchConfiguration(
        bundleID: Self.bundleID, bundleName: nil, arguments: [], environment: environment, waitForDebugger: false,
        launchMode: .relaunchIfRunning))
    let session = try await simulator.codeInjection.inject(into: .application(bundleID: Self.bundleID, reattach: true))

    let capture = try await simulator.audioCapture.start()
    let recording = try await simulator.videoRecording.start(
      toFile: directory.appendingPathComponent("recording.mp4").path,
      configuration: VideoStreamConfiguration(
        format: .compressedVideo(withCodec: .h264, transport: .annexB),
        encodeOptions: VideoEncodeOptions(framesPerSecond: 60, rateControl: nil, scaleFactor: 0.5, keyFrameRate: nil)))
    let played = try await session.execute(dylibAtPath: payload, symbol: "CodeInjectionPayloadFlashAndClick")
    let video = try await recording.stop()
    let wav = directory.appendingPathComponent("audio.wav").path
    let captured = try await capture.stop(writingMixTo: wav)
    try await session.close()
    let placement = try await recording.addAudio(fromWAV: wav, startingAtHostTime: captured.startHostTime)

    XCTAssertEqual(played, "\(Self.flashCount) \(Self.clickPeak)")
    XCTAssertEqual(captured.processes.filter { $0.frames > 0 }.map(\.name), ["Preferences"])
    XCTAssertGreaterThan(placement.frames, 0)
    // The capture keeps the samples the app rendered, so each click peaks where the app made it.
    let peaks = try Self.clickPeaks(inWAV: wav)
    XCTAssertEqual(peaks.count, Self.flashCount, "click peaks \(peaks)")
    for peak in peaks {
      XCTAssertEqual(peak, Self.clickPeak, accuracy: 0.005)
    }
    let flashes = try await Self.flashOnsets(in: video)
    let clicks = try await Self.clickOnsets(in: video)
    XCTAssertEqual(flashes.count, Self.flashCount, "flashes at \(flashes)")
    XCTAssertEqual(clicks.count, Self.flashCount, "clicks at \(clicks)")
    let offsets = zip(clicks, flashes).map { $0 - $1 }.sorted()
    let median = try XCTUnwrap(offsets.isEmpty ? nil : offsets[offsets.count / 2])
    XCTAssertLessThan(abs(median), Self.syncTolerance, "each click minus its flash: \(offsets)")
    XCTAssertLessThan(offsets.map { abs($0 - median) }.max() ?? 0, Self.jitterTolerance, "each click minus its flash: \(offsets)")
  }

  // MARK: - Reading the recording

  /// When the screen turns green, in seconds of the recording.
  private static func flashOnsets(in url: URL) async throws -> [Double] {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first, "the recording has no video track")
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    XCTAssertTrue(reader.startReading())
    var onsets: [Double] = []
    var flashing = false
    while let sample = output.copyNextSampleBuffer() {
      guard let image = CMSampleBufferGetImageBuffer(sample) else {
        continue
      }
      let green = isGreen(atCenterOf: image)
      if green && !flashing {
        onsets.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
      }
      flashing = green
    }
    return onsets
  }

  private static func isGreen(atCenterOf image: CVPixelBuffer) -> Bool {
    CVPixelBufferLockBaseAddress(image, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(image) else {
      return false
    }
    let pixel = base.advanced(by: CVPixelBufferGetHeight(image) / 2 * CVPixelBufferGetBytesPerRow(image) + CVPixelBufferGetWidth(image) / 2 * 4)
      .assumingMemoryBound(to: UInt8.self)
    // BGRA.
    return pixel[1] > 128 && pixel[0] < 100 && pixel[2] < 100
  }

  /// When each click starts, in seconds of the recording, read from its audio track.
  private static func clickOnsets(in url: URL) async throws -> [Double] {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    let track = try XCTUnwrap(tracks.first, "the recording has no audio track")
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false, AVNumberOfChannelsKey: 1,
      ])
    reader.add(output)
    XCTAssertTrue(reader.startReading())
    var start: Double?
    var rate = 0.0
    var samples: [Float] = []
    while let sample = output.copyNextSampleBuffer() {
      if start == nil, let format = CMSampleBufferGetFormatDescription(sample) {
        start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        rate = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mSampleRate ?? 0
      }
      guard let block = CMSampleBufferGetDataBuffer(sample) else {
        continue
      }
      var data = Data(count: CMBlockBufferGetDataLength(block))
      data.withUnsafeMutableBytes { bytes in
        if let base = bytes.baseAddress {
          CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: base)
        }
      }
      samples += data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
    let first = try XCTUnwrap(start)
    return onsets(in: samples, rate: rate).map { first + $0 }
  }

  /// The click peaks in a two-channel float WAV that the capture wrote.
  private static func clickPeaks(inWAV path: String) throws -> [Float] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let interleaved = data.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let left = stride(from: 0, to: interleaved.count, by: 2).map { interleaved[$0] }
    var peaks: [Float] = []
    var current: Float = 0
    var quiet = 0
    for value in left {
      if abs(value) > 0.05 {
        current = max(current, abs(value))
        quiet = 0
      } else if current > 0 {
        quiet += 1
        if quiet > 480 {
          peaks.append(current)
          current = 0
        }
      }
    }
    if current > 0 {
      peaks.append(current)
    }
    return peaks
  }

  /// Where a click starts after at least 50 ms of quiet, in seconds from the first sample.
  private static func onsets(in samples: [Float], rate: Double) -> [Double] {
    let quietRun = Int(rate * 0.05)
    var onsets: [Double] = []
    var quiet = quietRun
    for (index, value) in samples.enumerated() {
      if abs(value) > 0.25 {
        if quiet >= quietRun {
          onsets.append(Double(index) / rate)
        }
        quiet = 0
      } else if abs(value) < 0.05 {
        quiet += 1
      }
    }
    return onsets
  }
}
