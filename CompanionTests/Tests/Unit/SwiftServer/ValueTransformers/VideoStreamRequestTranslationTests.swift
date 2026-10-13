/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import FBVideoCore
import Foundation
import IDBGRPCSwift
import Testing

/// Pins the `video_stream` request → configuration translation. Every field is a proto3 scalar, so
/// what an unset one means is decided here and nowhere else; getting it wrong changes how every
/// stream is encoded without changing any caller.
@Suite
struct VideoStreamRequestTranslationTests {

  private func configuration(
    _ mutate: (inout Idb_VideoStreamRequest.Start) -> Void = { _ in }
  ) -> VideoStreamConfiguration {
    var start = Idb_VideoStreamRequest.Start()
    mutate(&start)
    return VideoStreamRequestTranslation.configuration(from: start)
  }

  // MARK: - Key frame rate

  @Test
  func anUnsetKeyFrameRateIsTheDefaultCadence() {
    // Zero survives into the configuration, and VideoToolbox reads a zero
    // MaxKeyFrameIntervalDuration as no limit at all -- so a stream that asked for nothing would
    // emit one keyframe and never sync again. Only nil takes the four-second default.
    #expect(configuration().keyFrameRate == 4)
  }

  @Test
  func aPositiveKeyFrameRateIsPassedThrough() {
    #expect(configuration { $0.keyFrameRate = 2 }.keyFrameRate == 2)
  }

  // MARK: - Scale

  @Test
  func anUnsetScaleFactorIsNoScaling() {
    // Zero would scale the output to nothing; unset has to mean the native size.
    #expect(configuration().scaleFactor == nil)
  }

  @Test
  func aPositiveScaleFactorIsPassedThrough() {
    #expect(configuration { $0.scaleFactor = 0.5 }.scaleFactor == 0.5)
  }

  // MARK: - Frame rate and rate control

  @Test
  func anUnsetFrameRateIsTheDisplaysOwnRate() {
    // Unlike a recording, which pins 30.
    #expect(configuration().framesPerSecond == nil)
    #expect(configuration { $0.fps = 15 }.framesPerSecond == 15)
  }

  @Test
  func eitherRateControlIsHonoured() {
    #expect(configuration().rateControl == .automatic)
    #expect(configuration { $0.avgBitrate = 800_000 }.rateControl == .bitrate(800_000))
    #expect(configuration { $0.compressionQuality = 0.75 }.rateControl == .quality(0.75))
  }

  // MARK: - Format

  @Test
  func everyWireFormatMaps() {
    #expect(configuration { $0.format = .h264 }.format == .compressedVideo(withCodec: .h264, transport: .annexB))
    #expect(configuration { $0.format = .rbga }.format == .bgra)
    #expect(configuration { $0.format = .mjpeg }.format == .mjpeg(encoder: .requireHardware))
    #expect(configuration { $0.format = .minicap }.format == .minicap)
  }

  @Test
  func aFormatThisCompanionCannotProduceFallsBackToH264() {
    // I420 is in the proto but unimplemented, and an unrecognized value is what a newer client's
    // format deserializes as. Both stream something playable rather than failing the call.
    #expect(configuration { $0.format = .i420 }.format == .compressedVideo(withCodec: .h264, transport: .annexB))
    #expect(
      configuration { $0.format = .UNRECOGNIZED(99) }.format
        == .compressedVideo(withCodec: .h264, transport: .annexB))
  }
}
