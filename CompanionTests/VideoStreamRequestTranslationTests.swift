/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import IDBGRPCSwift
import XCTest

/// Pins the `video_stream` request → configuration translation. Every field is a proto3 scalar, so
/// what an unset one means is decided here and nowhere else; getting it wrong changes how every
/// stream is encoded without changing any caller.
final class VideoStreamRequestTranslationTests: XCTestCase {

  private func configuration(
    _ mutate: (inout Idb_VideoStreamRequest.Start) -> Void = { _ in }
  ) -> FBVideoStreamConfiguration {
    var start = Idb_VideoStreamRequest.Start()
    mutate(&start)
    return VideoStreamRequestTranslation.configuration(from: start)
  }

  // MARK: - Key frame rate

  func testAnUnsetKeyFrameRateIsTheDefaultCadence() {
    // Zero survives into the configuration, and VideoToolbox reads a zero
    // MaxKeyFrameIntervalDuration as no limit at all -- so a stream that asked for nothing would
    // emit one keyframe and never sync again. Only nil takes the four-second default.
    XCTAssertEqual(configuration().keyFrameRate, 4)
  }

  func testAPositiveKeyFrameRateIsPassedThrough() {
    XCTAssertEqual(configuration { $0.keyFrameRate = 2 }.keyFrameRate, 2)
  }

  // MARK: - Scale

  func testAnUnsetScaleFactorIsNoScaling() {
    // Zero would scale the output to nothing; unset has to mean the native size.
    XCTAssertNil(configuration().scaleFactor)
  }

  func testAPositiveScaleFactorIsPassedThrough() {
    XCTAssertEqual(configuration { $0.scaleFactor = 0.5 }.scaleFactor, 0.5)
  }

  // MARK: - Frame rate and rate control

  func testAnUnsetFrameRateIsTheDisplaysOwnRate() {
    // Unlike a recording, which pins 30.
    XCTAssertNil(configuration().framesPerSecond)
    XCTAssertEqual(configuration { $0.fps = 15 }.framesPerSecond, 15)
  }

  func testEitherRateControlIsHonoured() {
    XCTAssertEqual(configuration().rateControl, .automatic)
    XCTAssertEqual(configuration { $0.avgBitrate = 800_000 }.rateControl, .bitrate(800_000))
    XCTAssertEqual(configuration { $0.compressionQuality = 0.75 }.rateControl, .quality(0.75))
  }

  // MARK: - Format

  func testEveryWireFormatMaps() {
    XCTAssertEqual(configuration { $0.format = .h264 }.format, .compressedVideo(withCodec: .h264, transport: .annexB))
    XCTAssertEqual(configuration { $0.format = .rbga }.format, .bgra)
    XCTAssertEqual(configuration { $0.format = .mjpeg }.format, .mjpeg(encoder: .requireHardware))
    XCTAssertEqual(configuration { $0.format = .minicap }.format, .minicap)
  }

  func testAFormatThisCompanionCannotProduceFallsBackToH264() {
    // I420 is in the proto but unimplemented, and an unrecognized value is what a newer client's
    // format deserializes as. Both stream something playable rather than failing the call.
    XCTAssertEqual(configuration { $0.format = .i420 }.format, .compressedVideo(withCodec: .h264, transport: .annexB))
    XCTAssertEqual(
      configuration { $0.format = .UNRECOGNIZED(99) }.format,
      .compressedVideo(withCodec: .h264, transport: .annexB))
  }
}
