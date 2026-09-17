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

  private static let lazyConfiguration = VideoStreamConfiguration(
    format: .bgra, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)

  private struct Started {
    let stream: SimulatorVideoStream
    let pusher: RecordingFramePusher
    let surface: FakeFramebufferSurface
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
    return Started(stream: stream, pusher: pusher, surface: surface, ioSurface: ioSurface, logger: logger)
  }

  func testPushesArePacedToOneDisplayIntervalApart() async throws {
    let started = try await startStream()
    defer { Task { try? await started.stream.stopStreaming() } }
    let pushInProgress = DispatchSemaphore(value: 0)
    started.pusher.onWrite = {
      pushInProgress.signal()
      usleep(2_000)
    }

    // The second signal lands while the first push is in progress; the third right after the second.
    started.surface.frameRendered?()
    XCTAssertEqual(pushInProgress.wait(timeout: .now() + 2), .success, "the first signal must start a push")
    started.surface.frameRendered?()
    started.surface.frameRendered?()

    for _ in 0..<200 where started.pusher.writes.count < 2 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    let writes = started.pusher.writes
    XCTAssertGreaterThanOrEqual(writes.count, 2, "a signal during a push must still be pushed")
    XCTAssertLessThanOrEqual(writes.count, 3, "three signals cannot produce more than three pushes")
    for (earlier, later) in zip(writes, writes.dropFirst()) {
      XCTAssertGreaterThanOrEqual(later.time - earlier.time, 1.0 / 60.0, "consecutive pushes must be a display interval apart")
    }
  }

  func testFrameTimingReferenceIsTheMonotonicClock() async throws {
    let started = try await startStream()
    defer { Task { try? await started.stream.stopStreaming() } }

    await started.stream.pushFrame(forceKeyFrame: false)
    await started.stream.pushFrame(forceKeyFrame: false)

    let writes = started.pusher.writes
    XCTAssertEqual(writes.count, 2)
    let reference = try XCTUnwrap(writes.first?.timeAtFirstFrame)
    XCTAssertEqual(reference, ProcessInfo.processInfo.systemUptime, accuracy: 5, "frame timing reference must be a monotonic uptime reading")
    XCTAssertEqual(writes[1].timeAtFirstFrame, reference, "every frame shares the first frame's reference time")
    XCTAssertGreaterThanOrEqual(writes[1].frameDuration, 0)
  }

  func testEncodeSubmissionFailureIsLogged() async throws {
    let started = try await startStream()
    defer { Task { try? await started.stream.stopStreaming() } }
    started.pusher.error = VideoToolboxFramePusherError.failedToCompress(status: -12902)

    await started.stream.pushFrame(forceKeyFrame: false)

    XCTAssertEqual(started.pusher.writes.count, 1)
    let encodeFailureLogs = started.logger.messages.compactMap { $0 as? String }.filter { $0.contains("-12902") }
    XCTAssertEqual(encodeFailureLogs.count, 1, "an encode submission failure must be logged once: \(started.logger.messages)")
  }

  func testSurfaceWrittenDuringPushIsCountedAsTorn() async throws {
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
    XCTAssertEqual(stats.tornFrameCount, 1)
  }
}

/// A frame pusher that records what `pushFrame` hands it and can fail or act on demand.
// SAFETY: `writes` is guarded by `lock`; `error` and `onWrite` are set before the push under test.
// patternlint-disable-next-line unchecked-sendable
private final class RecordingFramePusher: FramePusher, @unchecked Sendable {
  struct Write {
    let time: TimeInterval
    let frameNumber: UInt
    let timeAtFirstFrame: TimeInterval
    let frameDuration: TimeInterval
    let forceKeyFrame: Bool
  }

  private let lock = NSLock()
  private var recorded: [Write] = []
  private var tornFrameCount: UInt = 0
  var error: Error?
  var onWrite: (() -> Void)?

  var writes: [Write] {
    lock.withLock { recorded }
  }

  func recordTornFrame() {
    lock.withLock { tornFrameCount += 1 }
  }

  func currentStats() -> VideoEncoderStats? {
    var stats = VideoEncoderStats()
    stats.tornFrameCount = lock.withLock { tornFrameCount }
    return stats
  }

  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: VideoStreamEdgeInsets) throws {}

  func tearDown() throws {}

  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: TimeInterval,
    frameDuration: TimeInterval,
    forceKeyFrame: Bool
  ) throws {
    let time = ProcessInfo.processInfo.systemUptime
    onWrite?()
    lock.withLock {
      recorded.append(Write(time: time, frameNumber: frameNumber, timeAtFirstFrame: timeAtFirstFrame, frameDuration: frameDuration, forceKeyFrame: forceKeyFrame))
    }
    if let error {
      throw error
    }
  }
}

extension SimulatorVideoStream {
  fileprivate func installFramePusher(_ pusher: any FramePusher & Sendable) {
    framePusher = pusher
  }
}
