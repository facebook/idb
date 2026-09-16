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

  private func makePusher(frameWriters: VideoStreamFrameWriters?) throws -> SimulatorVideoStreamFramePusher_VideoToolbox {
    let pusher = try SimulatorVideoStream.framePusher(
      configuration: configuration,
      compressionSessionProperties: [:],
      consumer: FBDataBuffer.accumulatingBuffer(),
      encodedSampleConsumerOverride: nil,
      frameWriters: frameWriters,
      logger: CapturingLogger())
    return try XCTUnwrap(pusher as? SimulatorVideoStreamFramePusher_VideoToolbox)
  }

  func testFramePushersShareTheStreamsTransportWriter() throws {
    // The MPEG-TS writer is a class, so `===` compares the writer itself, not a boxed copy.
    let shared = VideoStreamTransport.mpegts.frameWriters(for: .h264)
    let first = try XCTUnwrap(makePusher(frameWriters: shared).timedMetadataWriter as? MPEGTSFrameWriter)
    let second = try XCTUnwrap(makePusher(frameWriters: shared).timedMetadataWriter as? MPEGTSFrameWriter)
    XCTAssertTrue(first === second)
    XCTAssertTrue(first === shared.timedMetadataWriter as AnyObject?)
  }

  func testStreamKeepsItsTransportWriterAcrossSurfaceSwaps() async throws {
    try VideoEncodingHostSupport.skipUnlessHardwareH264Encoding()
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface(width: 128, height: 128)
    let framebuffer = Framebuffer(surface: surface, logger: CapturingLogger())
    let stream = SimulatorVideoStream.make(framebuffer: framebuffer, configuration: configuration, logger: CapturingLogger())
    try await stream.startStreaming(FBDataBuffer.accumulatingBuffer())
    let firstWriter = await stream.frameWriters?.timedMetadataWriter as AnyObject?
    let first = try XCTUnwrap(firstWriter)

    surface.ioSurfaceChanged?(makeTestIOSurface(width: 256, height: 256))
    for _ in 0..<500 {
      try await Task.sleep(nanoseconds: 10_000_000)
      if await stream.pixelBuffer.map(CVPixelBufferGetWidth) == 256 { break }
    }
    let width = await stream.pixelBuffer.map(CVPixelBufferGetWidth)
    XCTAssertEqual(width, 256, "precondition: the swapped surface must have mounted")

    let secondWriter = await stream.frameWriters?.timedMetadataWriter as AnyObject?
    let second = try XCTUnwrap(secondWriter)
    XCTAssertTrue(first === second)
    try await stream.stopStreaming()
  }
}
