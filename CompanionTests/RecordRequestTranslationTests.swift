/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift
import XCTest

/// A target that records at whatever settings it chooses, which is what every conformer does until
/// it overrides `honorsRecordingConfiguration`.
private final class FixedConfigurationRecorder: VideoRecordingCommands {
  func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    FBVideoRecordingHandle { URL(fileURLWithPath: filePath) }
  }
}

private final class ConfigurableRecorder: VideoRecordingCommands {
  var honorsRecordingConfiguration: Bool { true }

  func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    FBVideoRecordingHandle { URL(fileURLWithPath: filePath) }
  }
}

/// Pins the `record` request → encode options translation and the resolved options → `Applied` echo.
/// These are the wire contract: a field that stops being honored, a rejection that changes class, or
/// an echo that reports something other than what was applied is a client-visible break.
final class RecordRequestTranslationTests: XCTestCase {

  // MARK: - Helpers

  private func start(_ mutate: (inout Idb_RecordRequest.Start) -> Void = { _ in }) -> Idb_RecordRequest.Start {
    var start = Idb_RecordRequest.Start()
    mutate(&start)
    return start
  }

  private func options(
    _ mutate: (inout Idb_RecordRequest.Start) -> Void = { _ in }
  ) throws -> FBVideoEncodeOptions? {
    try RecordRequestTranslation.encodeOptions(from: start(mutate))
  }

  private func assertRejected(
    _ mutate: (inout Idb_RecordRequest.Start) -> Void,
    mentioning fragment: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try options(mutate), file: file, line: line) { error in
      guard let status = error as? GRPCStatus else {
        return XCTFail("expected a GRPCStatus, got \(error)", file: file, line: line)
      }
      XCTAssertEqual(status.code, .invalidArgument, file: file, line: line)
      let message = status.message ?? ""
      XCTAssertTrue(
        message.contains(fragment), "\"\(message)\" does not name \(fragment)", file: file, line: line)
    }
  }

  // MARK: - The unconfigured path

  func testARequestThatSetsNothingIsTheHistoricalBehaviour() throws {
    // Every field defaults to 0 on the wire, so a client that predates them must still take the
    // unconfigured `startRecording(toFile:)` path rather than one built from defaults.
    XCTAssertNil(try options())
  }

  func testAnySingleOptionEntersTheConfiguredPath() throws {
    XCTAssertNotNil(try options { $0.fps = 15 })
    XCTAssertNotNil(try options { $0.scaleFactor = 0.5 })
    XCTAssertNotNil(try options { $0.avgBitrate = 1_000_000 })
    XCTAssertNotNil(try options { $0.compressionQuality = 0.5 })
    XCTAssertNotNil(try options { $0.keyFrameRate = 2 })
  }

  // MARK: - Translation

  func testTheOptionsAreCarriedThrough() throws {
    let options = try XCTUnwrap(
      try options {
        $0.fps = 15
        $0.scaleFactor = 0.5
        $0.avgBitrate = 1_000_000
        $0.keyFrameRate = 2
      })
    XCTAssertEqual(options.framesPerSecond, 15)
    XCTAssertEqual(options.scaleFactor, 0.5)
    XCTAssertEqual(options.rateControl, .bitrate(1_000_000))
    XCTAssertEqual(options.keyFrameRate, 2)
  }

  func testAnUnsetFrameRateIsTheRateRecordingHasAlwaysUsed() throws {
    // Unlike a stream, where unset means the display's own rate.
    XCTAssertEqual(try XCTUnwrap(try options { $0.scaleFactor = 0.5 }).framesPerSecond, 30)
  }

  func testAnUnsetScaleAndKeyFrameRateFallToTheFrameworkDefaults() throws {
    let options = try XCTUnwrap(try options { $0.fps = 15 })
    XCTAssertNil(options.scaleFactor)
    XCTAssertEqual(options.keyFrameRate, FBVideoEncodeOptions(framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil).keyFrameRate)
  }

  func testEitherRateControlIsHonoured() throws {
    XCTAssertEqual(try XCTUnwrap(try options { $0.avgBitrate = 800_000 }).rateControl, .bitrate(800_000))
    XCTAssertEqual(try XCTUnwrap(try options { $0.compressionQuality = 0.75 }).rateControl, .quality(0.75))
    XCTAssertEqual(try XCTUnwrap(try options { $0.fps = 15 }).rateControl, .automatic)
  }

  func testTheConfigurationRecordsH264() {
    // A recording is muxed to an mp4, so the format is not the caller's to choose.
    let configuration = RecordRequestTranslation.configuration(
      for: FBVideoEncodeOptions(framesPerSecond: 15, rateControl: nil, scaleFactor: nil, keyFrameRate: nil))
    XCTAssertEqual(configuration.format, .compressedVideo(withCodec: .h264, transport: .annexB))
    XCTAssertEqual(configuration.framesPerSecond, 15)
  }

  // MARK: - Rejections

  func testEveryNegativeIsRejectedByName() {
    assertRejected({ $0.scaleFactor = -0.5 }, mentioning: "scale_factor")
    assertRejected({ $0.avgBitrate = -1 }, mentioning: "avg_bitrate")
    assertRejected({ $0.keyFrameRate = -2 }, mentioning: "key_frame_rate")
    assertRejected({ $0.compressionQuality = -0.5 }, mentioning: "compression_quality")
  }

  func testACompressionQualityAboveOneIsRejected() {
    assertRejected({ $0.compressionQuality = 1.5 }, mentioning: "[0, 1]")
  }

  func testAScaleFactorAboveOneIsRejected() {
    // A recording can be shrunk but not enlarged: upscaling costs bitrate and adds no detail.
    assertRejected({ $0.scaleFactor = 2 }, mentioning: "shrunk but not enlarged")
  }

  func testTwoRateControlsAtOnceAreRejected() {
    // Silently preferring one would record at a rate the caller did not ask for.
    assertRejected(
      {
        $0.avgBitrate = 1_000_000
        $0.compressionQuality = 0.5
      }, mentioning: "set one")
  }

  func testNonFiniteValuesAreRejectedByName() {
    // A proto3 double can carry NaN or ±Infinity. None is a meaningful encode option: an unchecked
    // NaN slips past every range guard and reads as unset, and an Infinity reaches a trapping Int
    // conversion. Both must be rejected up front, named like every other bad value.
    assertRejected({ $0.scaleFactor = .nan }, mentioning: "scale_factor")
    assertRejected({ $0.avgBitrate = .infinity }, mentioning: "avg_bitrate")
    assertRejected({ $0.keyFrameRate = .nan }, mentioning: "key_frame_rate")
    assertRejected({ $0.compressionQuality = .infinity }, mentioning: "compression_quality")
  }

  func testAnAvgBitrateLargerThanIntIsRejected() {
    // Finite, but `Int(_:)` traps on a value at or beyond Int.max, which would crash the companion.
    assertRejected({ $0.avgBitrate = Double(Int.max) }, mentioning: "too large")
    assertRejected({ $0.avgBitrate = 1e300 }, mentioning: "too large")
  }

  // MARK: - Targets that cannot apply a configuration

  func testATargetThatDiscardsTheConfigurationRefuses() {
    XCTAssertThrowsError(
      try RecordRequestTranslation.requireHonoredConfiguration(FixedConfigurationRecorder(), describing: "a device")
    ) { error in
      guard let status = error as? GRPCStatus else {
        return XCTFail("expected a GRPCStatus, got \(error)")
      }
      // Not invalidArgument: the request is well formed and the same one succeeds on a simulator.
      XCTAssertEqual(status.code, .unimplemented)
      XCTAssertTrue(status.message?.contains("a device") ?? false, "the refusal must name the target")
    }
  }

  func testATargetThatAppliesTheConfigurationProceeds() {
    XCTAssertNoThrow(
      try RecordRequestTranslation.requireHonoredConfiguration(ConfigurableRecorder(), describing: "a simulator"))
  }

  // MARK: - The echo

  func testTheEchoReportsTheResolvedOptions() throws {
    let options = try XCTUnwrap(
      try options {
        $0.fps = 15
        $0.scaleFactor = 0.5
        $0.avgBitrate = 1_000_000
        $0.keyFrameRate = 2
      })
    guard case let .applied(applied) = RecordRequestTranslation.appliedResponse(options).output else {
      return XCTFail("the echo must be an Applied, not a payload")
    }
    XCTAssertEqual(applied.fps, 15)
    XCTAssertEqual(applied.scaleFactor, 0.5)
    XCTAssertEqual(applied.avgBitrate, 1_000_000)
    XCTAssertEqual(applied.keyFrameRate, 2)
  }

  func testTheEchoReportsTheDefaultsThatFilledTheGaps() throws {
    // The point of echoing at all: the client asked for one thing and learns the rest.
    let options = try XCTUnwrap(try options { $0.scaleFactor = 0.5 })
    guard case let .applied(applied) = RecordRequestTranslation.appliedResponse(options).output else {
      return XCTFail("the echo must be an Applied, not a payload")
    }
    XCTAssertEqual(applied.fps, 30)
    XCTAssertEqual(applied.keyFrameRate, 4)
    // No number to name for an automatic rate control, and no scaling reports as the 1:1 ratio.
    XCTAssertEqual(applied.avgBitrate, 0)
    XCTAssertEqual(
      RecordRequestTranslation.appliedResponse(
        FBVideoEncodeOptions(framesPerSecond: 15, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)
      ).applied.scaleFactor, 1)
  }

  /// The three rate controls have to land in three distinguishable echoes. Reporting a quality as
  /// bitrate 0 would make it read exactly like an automatic rate, which is the case the client most
  /// needs to tell it apart from.
  func testEachRateControlEchoesInItsOwnField() throws {
    let bitrate = try XCTUnwrap(try options { $0.avgBitrate = 800_000 })
    XCTAssertEqual(RecordRequestTranslation.appliedResponse(bitrate).applied.avgBitrate, 800_000)
    XCTAssertEqual(RecordRequestTranslation.appliedResponse(bitrate).applied.compressionQuality, 0)

    let quality = try XCTUnwrap(try options { $0.compressionQuality = 0.75 })
    XCTAssertEqual(RecordRequestTranslation.appliedResponse(quality).applied.compressionQuality, 0.75)
    XCTAssertEqual(RecordRequestTranslation.appliedResponse(quality).applied.avgBitrate, 0)

    let automatic = try XCTUnwrap(try options { $0.fps = 15 })
    XCTAssertEqual(RecordRequestTranslation.appliedResponse(automatic).applied.avgBitrate, 0)
    XCTAssertEqual(RecordRequestTranslation.appliedResponse(automatic).applied.compressionQuality, 0)
  }
}
