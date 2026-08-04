/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import CoreVideo
import FBControlCore
@testable import FBSimulatorControl
import VideoToolbox
import XCTest

final class FBSimulatorVideoStreamCallbackTests: XCTestCase {

  // MARK: - Helpers

  private func makeReadySampleBuffer() -> CMSampleBuffer {
    createH264SampleBuffer()
  }

  private func makeNotReadySampleBuffer() -> CMSampleBuffer {
    createNotReadySampleBuffer()
  }

  // MARK: - Tests

  func testWarmupFramesSuppressed() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // Send 5 not-ready buffers (simulates warmup)
    for _ in 0..<5 {
      let notReady = makeNotReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    // No per-frame messages during warmup
    for msg in logger.messages {
      XCTAssertFalse((msg as! String).contains("Sample Buffer is not ready"), "Should not log per-frame not-ready messages during warmup")
    }

    // Now send a ready buffer to complete warmup
    let ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    // Should have a single warmup message
    var warmupMessageCount: UInt = 0
    for msg in logger.messages {
      if (msg as! String).contains("Encoder warmed up after 5 skipped frames") {
        warmupMessageCount += 1
      }
    }
    XCTAssertEqual(warmupMessageCount, 1, "Should log exactly one warmup completion message")
    XCTAssertTrue(pusher.warmupComplete)
  }

  func testStarvationDetectedDuringWarmup() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // Send 20 not-ready buffers without any success
    for _ in 0..<20 {
      let notReady = makeNotReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    var foundStarvationWarning = false
    for msg in logger.messages {
      if (msg as! String).contains("has not produced a frame after 20 attempts") {
        foundStarvationWarning = true
      }
    }
    XCTAssertTrue(foundStarvationWarning, "Should warn about possible starvation after 20 warmup frames")
    XCTAssertTrue(pusher.starvationWarningLogged)
  }

  func testPostWarmupStarvation() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // First, complete warmup with a ready buffer
    let ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    XCTAssertTrue(pusher.warmupComplete)

    // Now send 10 not-ready buffers post-warmup
    for _ in 0..<10 {
      let notReady = makeNotReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    var foundStarvationWarning = false
    for msg in logger.messages {
      if (msg as! String).contains("Encoder starvation: 10 consecutive frames not ready after warmup") {
        foundStarvationWarning = true
      }
    }
    XCTAssertTrue(foundStarvationWarning, "Should warn about post-warmup starvation after 10 consecutive failures")
    XCTAssertTrue(pusher.starvationWarningLogged)
  }

  func testEncodeErrorLogged() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    pusher.handleCompressedSampleBuffer(nil, encodeStatus: -12345, infoFlags: VTEncodeInfoFlags())

    var foundError = false
    for msg in logger.messages {
      if (msg as! String).contains("VideoToolbox encode error: OSStatus -12345") {
        foundError = true
      }
    }
    XCTAssertTrue(foundError, "Should log VideoToolbox encode error with status code")
    XCTAssertEqual(pusher.stats.callbackCount, 1)
  }

  func testFrameDroppedCountedAsFailure() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    pusher.handleCompressedSampleBuffer(nil, encodeStatus: noErr, infoFlags: .frameDropped)

    // Dropped frame should increment failure counter, not produce a per-frame log
    XCTAssertEqual(pusher.consecutiveNotReadyFrameCount, 1)
    XCTAssertEqual(pusher.stats.callbackCount, 1)
    XCTAssertEqual(UInt(logger.messages.count), 1, "Should only log the first-callback message, not per-frame drop messages")
  }

  func testDroppedFramesTriggersStarvationWarning() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // Send 20 dropped frames — should trigger starvation warning
    for _ in 0..<20 {
      pusher.handleCompressedSampleBuffer(nil, encodeStatus: noErr, infoFlags: .frameDropped)
    }

    var foundStarvationWarning = false
    for msg in logger.messages {
      if (msg as! String).contains("has not produced a frame after 20 attempts") {
        foundStarvationWarning = true
      }
    }
    XCTAssertTrue(foundStarvationWarning, "20 consecutive dropped frames should trigger starvation warning")
    XCTAssertEqual(UInt(logger.messages.count), 2, "Should produce the first-callback message and one starvation warning")
  }

  func testNoWarmupMessageWhenFirstFrameSucceeds() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // Send a ready buffer immediately
    let ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    XCTAssertTrue(pusher.warmupComplete)

    // No warmup message should be logged
    for msg in logger.messages {
      XCTAssertFalse((msg as! String).contains("Encoder warmed up"), "Should not log warmup message when first frame succeeds immediately")
    }
  }

  func testPeriodicStatsNotLoggedBeforeInterval() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // Send a few successful frames — stats interval hasn't elapsed
    for _ in 0..<3 {
      let ready = makeReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    for msg in logger.messages {
      XCTAssertFalse((msg as! String).contains("Video stats"), "Should not log stats before interval elapses")
    }
  }

  func testPeriodicStatsLoggedAfterInterval() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // Send one frame to initialize timing
    var ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    // Backdate statsTimer by 6 seconds to trigger stats on next frame
    var timer = pusher.statsTimer
    timer.backdateForTesting(by: 6.0)
    pusher.statsTimer = timer

    ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    var foundStats = false
    for msg in logger.messages {
      if (msg as! String).contains("Video stats") {
        foundStats = true
      }
    }
    XCTAssertTrue(foundStats, "Should log stats after interval elapses")
  }

  func testPeriodicStatsCountersAccurate() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // 3 successful writes
    for _ in 0..<3 {
      let ready = makeReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    // 2 dropped frames
    for _ in 0..<2 {
      pusher.handleCompressedSampleBuffer(nil, encodeStatus: noErr, infoFlags: .frameDropped)
    }

    // 1 encode error
    pusher.handleCompressedSampleBuffer(nil, encodeStatus: -12345, infoFlags: VTEncodeInfoFlags())

    // Verify counters
    XCTAssertEqual(pusher.stats.writeCount, 3)
    XCTAssertEqual(pusher.stats.dropCount, 2)
    XCTAssertEqual(pusher.stats.encodeErrorCount, 1)
    XCTAssertEqual(pusher.stats.callbackCount, 6)

    // Backdate to trigger stats log
    var timer = pusher.statsTimer
    timer.backdateForTesting(by: 6.0)
    pusher.statsTimer = timer

    let ready = makeReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(ready, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    var foundStats = false
    for msg in logger.messages {
      let s = msg as! String
      if s.contains("Video stats")
        && s.contains("4 written")
        && s.contains("2 dropped")
        && s.contains("1 encode errors")
      {
        foundStats = true
      }
    }
    XCTAssertTrue(foundStats, "Stats message should contain accurate counters")
  }

  func testPeriodicStatsDuringWarmup() {
    let logger = FBCapturingLogger()
    let pusher = createTestVideoStreamPusher(logger)

    // Send 10 not-ready buffers (write failures during warmup)
    for _ in 0..<10 {
      let notReady = makeNotReadySampleBuffer()
      pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())
    }

    // Backdate to trigger stats log
    var timer = pusher.statsTimer
    timer.backdateForTesting(by: 6.0)
    pusher.statsTimer = timer

    // Send one more not-ready buffer to trigger the stats log
    let notReady = makeNotReadySampleBuffer()
    pusher.handleCompressedSampleBuffer(notReady, encodeStatus: noErr, infoFlags: VTEncodeInfoFlags())

    var foundStats = false
    for msg in logger.messages {
      let s = msg as! String
      if s.contains("Video stats")
        && s.contains("0 written")
        && s.contains("11 write failures")
      {
        foundStats = true
      }
    }
    XCTAssertTrue(foundStats, "Stats during warmup should show 0 written and write failures")
  }
}

/// Tests for the bitmap (BGRA) frame pusher's raw byte contract.
final class FBSimulatorVideoStreamBitmapPusherTests: XCTestCase {

  // MARK: - Helpers

  /// Creates an IOSurface-backed BGRA pixel buffer filled with a constant byte.
  private func makeBGRAPixelBuffer(width: Int, height: Int, fill: UInt8) -> CVPixelBuffer {
    let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
    precondition(status == kCVReturnSuccess, "CVPixelBufferCreate failed: \(status)")
    let buffer = pixelBuffer!

    CVPixelBufferLockBaseAddress(buffer, [])
    if let base = CVPixelBufferGetBaseAddress(buffer) {
      memset(base, Int32(fill), CVPixelBufferGetDataSize(buffer))
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
  }

  // MARK: - Tests

  func testBitmapPusherWritesRawPixelBytes() throws {
    let buffer = makeBGRAPixelBuffer(width: 16, height: 8, fill: 0xAB)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let pusher = FBSimulatorVideoStreamFramePusher_Bitmap(consumer: consumer, scaleFactor: nil)

    let zeroInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0)
    try pusher.setup(with: buffer, edgeInsets: zeroInsets)
    try pusher.writeEncodedFrame(
      buffer,
      frameNumber: 0,
      timeAtFirstFrame: 0,
      frameDuration: 0,
      forceKeyFrame: false
    )

    // The bitmap pusher writes the raw pixel buffer bytes through to the consumer, unframed.
    let output = consumer.data()
    XCTAssertEqual(output.count, CVPixelBufferGetDataSize(buffer))
    XCTAssertFalse(output.isEmpty)
    XCTAssertTrue(output.allSatisfy { $0 == 0xAB }, "Raw BGRA bytes should pass through unchanged")

    try pusher.tearDown()
  }

  func testBitmapPusherWithoutScaleDoesNotResize() throws {
    let buffer = makeBGRAPixelBuffer(width: 16, height: 8, fill: 0x10)
    let consumer = FBDataBuffer.accumulatingBuffer()
    // nil scaleFactor → no pixel transfer session, raw passthrough at source dimensions.
    let pusher = FBSimulatorVideoStreamFramePusher_Bitmap(consumer: consumer, scaleFactor: nil)

    let zeroInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0)
    try pusher.setup(with: buffer, edgeInsets: zeroInsets)
    try pusher.writeEncodedFrame(
      buffer,
      frameNumber: 0,
      timeAtFirstFrame: 0,
      frameDuration: 0,
      forceKeyFrame: false
    )

    // Output is exactly one source-sized frame.
    XCTAssertEqual(consumer.data().count, CVPixelBufferGetDataSize(buffer))

    try pusher.tearDown()
  }
}

/// End-to-end delivery tests for `FBSimulatorVideoStream` over a fake display surface: a framebuffer
/// event fired on the fake must come out of the stream as pushed frame data. These pin the
/// behavioral contract of the delivery chain (surface event → framebuffer → stream cadence →
/// pusher → consumer) through the public API only, so they must keep passing unchanged as the
/// internal delivery mechanism evolves.
final class FBSimulatorVideoStreamDeliveryTests: XCTestCase {

  /// `.bgra` and no `framesPerSecond`: the lazy (variable-frame-rate) cadence with the bitmap
  /// pusher, so pushes reach the consumer without any encoder in the way.
  private static let lazyConfiguration = FBVideoStreamConfiguration(
    format: .bgra, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)

  private func makeStream(
    surface: FakeFramebufferSurface,
    configuration: FBVideoStreamConfiguration = lazyConfiguration
  ) -> FBSimulatorVideoStream {
    let framebuffer = FBFramebuffer(surface: surface, logger: FBCapturingLogger())
    return FBSimulatorVideoStream.make(
      framebuffer: framebuffer, configuration: configuration, logger: FBCapturingLogger())
  }

  /// Poll until `condition` holds, or fail after ~5s. The delivery chain hops queues/tasks, so
  /// tests await outcomes rather than assuming synchronous effects.
  private func expectEventually(
    _ message: String,
    condition: () -> Bool
  ) async throws {
    for _ in 0..<500 {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condition(), message)
  }

  /// Wait for the byte count to stop growing (two identical samples 100ms apart) so a test can
  /// take a baseline that in-flight attach-time pushes cannot disturb.
  private func settledCount(of consumer: any FBAccumulatingBuffer) async throws -> Int {
    var previous = -1
    for _ in 0..<50 {
      let current = consumer.data().count
      if current == previous {
        return current
      }
      previous = current
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    return previous
  }

  func testFrameRenderedSignalPushesFrame() async throws {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = makeStream(surface: surface)

    try await stream.startStreaming(consumer)
    let baseline = try await settledCount(of: consumer)

    surface.frameRendered?()

    try await expectEventually("a rendered-frame signal must produce a pushed frame") {
      consumer.data().count > baseline
    }
    try await stream.stopStreaming()
  }

  func testPushesTrackFrameSignalsAndQuietFramebufferPushesNothing() async throws {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = makeStream(surface: surface)

    try await stream.startStreaming(consumer)
    let baseline = try await settledCount(of: consumer)

    surface.frameRendered?()
    try await expectEventually("first signal pushes") { consumer.data().count > baseline }
    let afterFirst = try await settledCount(of: consumer)

    // Variable-frame-rate contract: no signal, no push.
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(consumer.data().count, afterFirst, "a quiet framebuffer must not push frames in .lazy mode")

    surface.frameRendered?()
    try await expectEventually("a signal after a quiet period pushes again") {
      consumer.data().count > afterFirst
    }
    try await stream.stopStreaming()
  }

  func testSurfaceArrivingAfterAttachMountsAndStartsStream() async throws {
    let surface = FakeFramebufferSurface()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = makeStream(surface: surface)

    // With no immediately-available surface, startStreaming suspends until the first
    // surface-change event mounts. Deliver it once the callbacks are registered.
    async let started: Void = stream.startStreaming(consumer)
    try await expectEventually("attach must register the surface callbacks") {
      surface.ioSurfaceChanged != nil
    }
    surface.ioSurfaceChanged?(makeTestIOSurface())
    try await started

    try await expectEventually("mounting the first surface must push a frame") {
      !consumer.data().isEmpty
    }
    try await stream.stopStreaming()
  }

  func testSurfaceSwapRemountsAndPushes() async throws {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let stream = makeStream(surface: surface)

    try await stream.startStreaming(consumer)
    let baseline = try await settledCount(of: consumer)

    surface.ioSurfaceChanged?(makeTestIOSurface(width: 32, height: 32))

    try await expectEventually("a surface swap must remount and push a frame") {
      consumer.data().count > baseline
    }
    try await stream.stopStreaming()
  }
}
