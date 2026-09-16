/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
import FBControlCore
@testable import FBSimulatorControl
import IOSurface
import XCTest

/// What `pushFrame` hands the frame pusher and how it reports the pusher's outcome, observed
/// through a recording pusher installed in place of the real one.
final class SimulatorVideoStreamPushFrameTests: XCTestCase {

  private static let lazyConfiguration = FBVideoStreamConfiguration(
    format: .bgra, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)

  private struct Started {
    let stream: SimulatorVideoStream
    let pusher: RecordingFramePusher
    let ioSurface: IOSurface
    let logger: CapturingLogger
  }

  private func startStream() async throws -> Started {
    let surface = FakeFramebufferSurface()
    let ioSurface = makeTestIOSurface()
    surface.immediateSurface = ioSurface
    let logger = CapturingLogger()
    let framebuffer = Framebuffer(surface: surface, logger: logger)
    let stream = SimulatorVideoStream.make(framebuffer: framebuffer, configuration: Self.lazyConfiguration, logger: logger)
    try await stream.startStreaming(FBDataBuffer.accumulatingBuffer())
    let pusher = RecordingFramePusher()
    await stream.installFramePusher(pusher)
    return Started(stream: stream, pusher: pusher, ioSurface: ioSurface, logger: logger)
  }

  func testFrameTimingReferenceIsTheWallClock() async throws {
    let started = try await startStream()
    defer { Task { try? await started.stream.stopStreaming() } }

    await started.stream.pushFrame(forceKeyFrame: false)
    await started.stream.pushFrame(forceKeyFrame: false)

    let writes = started.pusher.writes
    XCTAssertEqual(writes.count, 2)
    let reference = try XCTUnwrap(writes.first?.timeAtFirstFrame)
    // BUG: frames are timed against CFAbsoluteTimeGetCurrent, which steps with NTP adjustments and can
    // hand the encoder a non-increasing timestamp — flipped to the monotonic uptime clock in the
    // following commit.
    XCTAssertEqual(reference, CFAbsoluteTimeGetCurrent(), accuracy: 5, "frame timing reference must be a wall-clock reading")
    XCTAssertEqual(writes[1].timeAtFirstFrame, reference, "every frame shares the first frame's reference time")
    XCTAssertGreaterThanOrEqual(writes[1].frameDuration, 0)
  }

  func testEncodeSubmissionFailureIsSwallowed() async throws {
    let started = try await startStream()
    defer { Task { try? await started.stream.stopStreaming() } }
    started.pusher.error = SimulatorVideoStreamError.failedToCompress(status: -12902)

    await started.stream.pushFrame(forceKeyFrame: false)

    XCTAssertEqual(started.pusher.writes.count, 1)
    let encodeFailureLogs = started.logger.messages.compactMap { $0 as? String }.filter { $0.contains("-12902") }
    // BUG: a frame the encoder refuses leaves no trace — flipped to a logged failure in the following commit.
    XCTAssertEqual(encodeFailureLogs, [])
  }

  func testSurfaceWrittenDuringPushIsNotCountedAsTorn() async throws {
    let started = try await startStream()
    defer { Task { try? await started.stream.stopStreaming() } }
    let ioSurface = started.ioSurface
    started.pusher.onWrite = {
      // The render server writing into the surface while the frame is being read.
      try? ioSurface.lock(options: [], seed: nil)
      ioSurface.baseAddress.assumingMemoryBound(to: UInt8.self)[0] ^= 0xFF
      try? ioSurface.unlock(options: [], seed: nil)
    }

    await started.stream.pushFrame(forceKeyFrame: false)

    XCTAssertEqual(started.pusher.writes.count, 1)
    let stats = await started.stream.currentEncoderStats()
    // BUG: tearing is checked on the encoder's private NV12 copy, which nothing else writes, so a
    // surface modified mid-read is never counted — flipped to 1 in the following commit.
    XCTAssertEqual(stats.tornFrameCount, 0)
  }
}

/// A frame pusher that records what `pushFrame` hands it and can fail or act on demand.
// SAFETY: `writes` is guarded by `lock`; `error` and `onWrite` are set before the push under test.
// patternlint-disable-next-line unchecked-sendable
private final class RecordingFramePusher: SimulatorVideoStreamFramePusher, @unchecked Sendable {
  struct Write {
    let frameNumber: UInt
    let timeAtFirstFrame: CFTimeInterval
    let frameDuration: CFTimeInterval
    let forceKeyFrame: Bool
  }

  private let lock = NSLock()
  private var recorded: [Write] = []
  var error: Error?
  var onWrite: (() -> Void)?

  var writes: [Write] {
    lock.withLock { recorded }
  }

  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: VideoStreamEdgeInsets) throws {}

  func tearDown() throws {}

  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: CFTimeInterval,
    frameDuration: CFTimeInterval,
    forceKeyFrame: Bool
  ) throws {
    onWrite?()
    lock.withLock {
      recorded.append(Write(frameNumber: frameNumber, timeAtFirstFrame: timeAtFirstFrame, frameDuration: frameDuration, forceKeyFrame: forceKeyFrame))
    }
    if let error {
      throw error
    }
  }
}

extension SimulatorVideoStream {
  fileprivate func installFramePusher(_ pusher: any SimulatorVideoStreamFramePusher & Sendable) {
    framePusher = pusher
  }
}
