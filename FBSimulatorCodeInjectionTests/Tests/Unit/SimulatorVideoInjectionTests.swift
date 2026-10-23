/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import AVFoundation
@testable import FBSimulatorCodeInjection
import Foundation
import Testing

@Suite
struct SimulatorVideoInjectionTests {
  private typealias Commands = SimulatorVideoInjectionCommands
  private typealias Report = SimulatorVideoInjectionCommands.InjectionReport

  private static let shim = "/tmp/current/libShimulator-iOS.dylib"

  @Test
  func armsAnAppLaunchedWithTheShimWhileInjecting() {
    let original = ["DYLD_INSERT_LIBRARIES": "/tmp/libProfiler.dylib:\(Self.shim)", "MAGIC": "unchanged"]
    let (prepared, skipped) = Commands.appLaunchEnvironment(original, injecting: true)
    #expect(skipped == nil)
    #expect(prepared["IDB_VIDEO_INJECTION"] == "1")
    #expect(prepared.filter { $0.key != "IDB_VIDEO_INJECTION" } == original)
  }

  @Test
  func leavesTheEnvironmentAloneWhenNotInjecting() {
    let original = ["DYLD_INSERT_LIBRARIES": Self.shim]
    let (prepared, skipped) = Commands.appLaunchEnvironment(original, injecting: false)
    #expect(prepared == original)
    #expect(skipped == nil)
  }

  @Test
  func explainsALaunchWithoutTheShim() {
    for original in [[:], ["DYLD_INSERT_LIBRARIES": "/tmp/libProfiler.dylib"]] {
      let (prepared, skipped) = Commands.appLaunchEnvironment(original, injecting: true)
      #expect(prepared == original)
      #expect(skipped == "libShimulator-iOS.dylib is not in DYLD_INSERT_LIBRARIES")
    }
  }

  @Test
  func keepsTheCallersArmingValue() {
    for value in ["1", "0", ""] {
      let original = ["DYLD_INSERT_LIBRARIES": Self.shim, "IDB_VIDEO_INJECTION": value]
      let (prepared, skipped) = Commands.appLaunchEnvironment(original, injecting: true)
      #expect(prepared == original)
      #expect(skipped == nil)
    }
  }

  @Test
  func reportsTheProcessesShowingTheVideo() {
    let reports = [
      Report(state: .showing, process: "Zebra"),
      Report(state: .showing, process: "Camera"),
      Report(state: .showing, process: "Exited", connected: false),
      Report(state: .completed, process: "Looper"),
    ]
    #expect(Commands.progress(of: reports, loop: true) == .showing(["Camera", "Zebra"]))
    #expect(Commands.progress(of: [], loop: false) == .showing([]))
  }

  @Test
  func completesOnlyWithoutLooping() {
    let reports = [Report(state: .showing, process: "Camera"), Report(state: .completed, process: "Done", connected: false)]
    #expect(Commands.progress(of: reports, loop: false) == .completed)
    #expect(Commands.progress(of: reports, loop: true) == .showing(["Camera"]))
  }

  @Test
  func anyFailureFailsTheInjection() {
    let reports = [
      Report(state: .completed, process: "Done"),
      Report(state: .failed, process: "Broken", message: "no playable video track"),
    ]
    #expect(Commands.progress(of: reports, loop: false) == .failed(process: "Broken", message: "no playable video track"))
  }

  @Test
  func copiesKeepTheInputsExtension() {
    let stem = "/tmp/idb-shimulator-501/ABCD.video"
    #expect(Commands.copyPath(stem: stem, camera: "back", of: URL(fileURLWithPath: "/x/in.MOV")) == "\(stem)-back.MOV")
    #expect(Commands.copyPath(stem: stem, camera: "front", of: URL(fileURLWithPath: "/x/in")) == "\(stem)-front")
  }

  @Test
  func rejectsInputsThatAreNotPlayableVideoFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("idb-video-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let text = directory.appendingPathComponent("notes.mov")
    try Data("not a video".utf8).write(to: text)

    for input in [directory.appendingPathComponent("missing.mov"), directory] {
      await #expect {
        try await Commands.requireVideo(input)
      } throws: { error in
        if case .inputUnreadable = error as? VideoInjectionError { return true }
        return false
      }
    }
    await #expect {
      try await Commands.requireVideo(text)
    } throws: { error in
      if case .noVideoTrack = error as? VideoInjectionError { return true }
      return false
    }
  }

  @Test
  func acceptsAVideoFile() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("idb-video-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: url) }
    try await writeVideo(to: url)
    try await Commands.requireVideo(url)
  }

  private func writeVideo(to url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<2 {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(for: .milliseconds(5))
      }
      var buffer: CVPixelBuffer?
      CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
      let pixels = try #require(buffer)
      #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
  }
}
