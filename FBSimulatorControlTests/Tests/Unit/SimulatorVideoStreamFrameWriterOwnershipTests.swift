/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Who owns the transport frame writer across the frame pushers a stream creates — one per mounted
/// surface — since the writer carries per-stream state (MPEG-TS continuity counters, the fMP4 init
/// segment and sequence numbers) that must not restart when the surface is swapped.
final class SimulatorVideoStreamFrameWriterOwnershipTests: XCTestCase {

  private let configuration = VideoStreamConfiguration(
    format: .compressedVideo(withCodec: .h264, transport: .mpegts),
    framesPerSecond: nil,
    rateControl: nil,
    scaleFactor: nil,
    keyFrameRate: nil)

  private func makePusher() throws -> SimulatorVideoStreamFramePusher_VideoToolbox {
    let pusher = try SimulatorVideoStream.framePusher(
      configuration: configuration,
      compressionSessionProperties: [:],
      consumer: FBDataBuffer.accumulatingBuffer(),
      encodedSampleConsumerOverride: nil,
      logger: CapturingLogger())
    return try XCTUnwrap(pusher as? SimulatorVideoStreamFramePusher_VideoToolbox)
  }

  func testEachFramePusherGetsItsOwnTransportWriter() throws {
    // The MPEG-TS writer is a class, so `===` compares the writer itself, not a boxed copy.
    let first = try XCTUnwrap(makePusher().timedMetadataWriter as? MPEGTSFrameWriter)
    let second = try XCTUnwrap(makePusher().timedMetadataWriter as? MPEGTSFrameWriter)
    // BUG: a surface swap builds a new pusher and with it a new transport writer, so MPEG-TS
    // continuity counters restart and fMP4 emits a second init segment mid-stream — flipped to a
    // writer shared across pushers in the following commit.
    XCTAssertFalse(first === second)
  }
}
