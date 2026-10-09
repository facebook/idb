/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
import FBControlCore
@testable import FBSimulatorControl
@testable import FBSimulatorVideo
import FBVideoCore
import IOSurface
import XCTest

/// How a stream prepares frame pushers for the displays it may switch to, and uses them on a switch.
final class SimulatorVideoStreamDisplaySwitchTests: XCTestCase {

  private let cover = VideoFrameSource(width: 20, height: 30, pixelFormat: kCVPixelFormatType_32BGRA)
  private let inner = VideoFrameSource(width: 40, height: 60, pixelFormat: kCVPixelFormatType_32BGRA)

  private struct Started {
    let stream: SimulatorVideoStream
    let surface: FakeFramebufferSurface
  }

  private func display(_ id: String, _ size: VideoFrameSource, active: Bool) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: id, activity: active ? .active : .inactive, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: size.width, height: size.height), scale: 2, rotation: .upright)
  }

  private func configuration(_ displays: [SimulatorDisplay]) -> SimulatorDisplayConfiguration {
    SimulatorDisplayConfiguration(
      generation: 1, displays: displays, active: displays.first(where: \.isActive).map { .identified($0) } ?? .unresolved, phase: .settled)
  }

  private func startStream() async throws -> Started {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface(width: cover.width, height: cover.height)
    let stream = SimulatorVideoStream(
      framebuffer: Framebuffer(surface: surface, logger: CapturingLogger()),
      configuration: VideoStreamConfiguration(format: .bgra, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil),
      edgeInsets: VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0),
      cadence: .lazy,
      logger: CapturingLogger())
    try await stream.startStreaming(FBDataBuffer.accumulatingBuffer())
    return Started(stream: stream, surface: surface)
  }

  private func waitUntil(_ condition: @escaping () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
    let deadline = Date(timeIntervalSinceNow: 5)
    while await !condition() {
      guard deadline.timeIntervalSinceNow > 0 else { return XCTFail("condition never held", file: file, line: line) }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  func testAConfigurationWithAnotherSurfaceSizePreparesAPusherForIt() async throws {
    let started = try await startStream()
    started.surface.configurationChanged?(configuration([display("cover", cover, active: true), display("inner", inner, active: false)]))
    try await waitUntil { await started.stream.spareFramePusher(for: self.inner) != nil }

    let spareForCover = await started.stream.spareFramePusher(for: cover)
    XCTAssertNil(spareForCover, "the mounted size needs no spare")
    try await started.stream.stopStreaming()
  }

  func testASwitchTakesThePreparedPusherAndKeepsTheOneItReplaces() async throws {
    let started = try await startStream()
    started.surface.configurationChanged?(configuration([display("cover", cover, active: true), display("inner", inner, active: false)]))
    try await waitUntil { await started.stream.spareFramePusher(for: self.inner) != nil }
    let mounted = await started.stream.mountedFramePusher
    let prepared = await started.stream.spareFramePusher(for: inner)

    started.surface.ioSurfaceChanged?(makeTestIOSurface(width: inner.width, height: inner.height))
    try await waitUntil { await started.stream.spareFramePusher(for: self.cover) != nil }

    let nowMounted = await started.stream.mountedFramePusher
    let kept = await started.stream.spareFramePusher(for: cover)
    XCTAssertEqual(nowMounted, prepared)
    XCTAssertEqual(kept, mounted)
    try await started.stream.stopStreaming()
  }

  func testASoleSurfaceSizePreparesNothingAndReplacesItsPusher() async throws {
    let started = try await startStream()
    started.surface.configurationChanged?(configuration([display("cover", cover, active: true)]))
    started.surface.ioSurfaceChanged?(makeTestIOSurface(width: inner.width, height: inner.height))
    try await waitUntil { await started.stream.mountedSource == self.inner }

    let preparing = await started.stream.preparesForDisplaySwitches
    let spareForCover = await started.stream.spareFramePusher(for: cover)
    XCTAssertFalse(preparing)
    XCTAssertNil(spareForCover)
    try await started.stream.stopStreaming()
  }

  func testTheFirstFrameAfterASwitchIsAKeyFrame() async throws {
    let started = try await startStream()
    started.surface.configurationChanged?(configuration([display("cover", cover, active: true), display("inner", inner, active: false)]))
    try await waitUntil { await started.stream.spareFramePusher(for: self.inner) != nil }
    let recording = KeyFrameRecordingPusher()
    await started.stream.replaceSpareFramePusher(for: inner, with: recording)

    started.surface.ioSurfaceChanged?(makeTestIOSurface(width: inner.width, height: inner.height))
    try await waitUntil { !recording.forcedKeyFrames.isEmpty }

    XCTAssertEqual(recording.forcedKeyFrames.first, true)
    try await started.stream.stopStreaming()
  }

  func testAKeptPusherHandsOnTheFramesItHoldsBeforeTheSwitch() async throws {
    let started = try await startStream()
    started.surface.configurationChanged?(configuration([display("cover", cover, active: true), display("inner", inner, active: false)]))
    try await waitUntil { await started.stream.spareFramePusher(for: self.inner) != nil }
    let recording = KeyFrameRecordingPusher()
    await started.stream.replaceMountedFramePusher(with: recording)

    started.surface.ioSurfaceChanged?(makeTestIOSurface(width: inner.width, height: inner.height))
    try await waitUntil { await started.stream.spareFramePusher(for: self.cover) != nil }

    XCTAssertEqual(recording.completedFrames, 1)
    XCTAssertFalse(recording.tornDown)
    try await started.stream.stopStreaming()
  }

  func testASurfaceInAnotherPixelFormatSetsUpItsOwnPusher() async throws {
    let started = try await startStream()
    started.surface.configurationChanged?(configuration([display("cover", cover, active: true), display("inner", inner, active: false)]))
    try await waitUntil { await started.stream.spareFramePusher(for: self.inner) != nil }
    let prepared = await started.stream.spareFramePusher(for: inner)

    started.surface.ioSurfaceChanged?(makeTestIOSurface(width: inner.width, height: inner.height, pixelFormat: kCVPixelFormatType_32ARGB))
    try await waitUntil { await started.stream.mountedSource?.pixelFormat == kCVPixelFormatType_32ARGB }

    let mounted = await started.stream.mountedFramePusher
    let stillSpare = await started.stream.spareFramePusher(for: inner)
    XCTAssertNotEqual(mounted, prepared)
    XCTAssertEqual(stillSpare, prepared)
    try await started.stream.stopStreaming()
  }

  func testStoppingTearsDownTheSparePushers() async throws {
    let started = try await startStream()
    started.surface.configurationChanged?(configuration([display("cover", cover, active: true), display("inner", inner, active: false)]))
    try await waitUntil { await started.stream.spareFramePusher(for: self.inner) != nil }
    let recording = KeyFrameRecordingPusher()
    await started.stream.replaceSpareFramePusher(for: inner, with: recording)

    try await started.stream.stopStreaming()

    XCTAssertTrue(recording.tornDown)
    let spareForInner = await started.stream.spareFramePusher(for: inner)
    XCTAssertNil(spareForInner)
  }
}

extension SimulatorVideoStream {
  fileprivate var mountedFramePusher: ObjectIdentifier? {
    framePusher.map { ObjectIdentifier($0) }
  }

  fileprivate var mountedSource: VideoFrameSource? {
    pixelBuffer.map(VideoFrameSource.init)
  }

  fileprivate func spareFramePusher(for size: VideoFrameSource) -> ObjectIdentifier? {
    guard let pusher = spareFramePushers.take(size) else { return nil }
    _ = spareFramePushers.keep(pusher, for: size)
    return ObjectIdentifier(pusher)
  }

  fileprivate func replaceMountedFramePusher(with pusher: any FramePusher & Sendable) {
    try? framePusher?.tearDown()
    framePusher = pusher
  }

  fileprivate func replaceSpareFramePusher(for size: VideoFrameSource, with pusher: any FramePusher & Sendable) {
    try? spareFramePushers.keep(pusher, for: size)?.tearDown()
  }
}

// SAFETY: every field is guarded by `lock`.
// patternlint-disable-next-line unchecked-sendable
private final class KeyFrameRecordingPusher: FramePusher, @unchecked Sendable {
  private let lock = NSLock()
  private var keyFrames: [Bool] = []
  private var tornDownFlag = false
  private var completions = 0

  var forcedKeyFrames: [Bool] { lock.withLock { keyFrames } }
  var tornDown: Bool { lock.withLock { tornDownFlag } }
  var completedFrames: Int { lock.withLock { completions } }

  func completeFrames() {
    lock.withLock { completions += 1 }
  }

  func setup(source: VideoFrameSource, edgeInsets: VideoStreamEdgeInsets) throws {}

  func tearDown() throws {
    lock.withLock { tornDownFlag = true }
  }

  func writeEncodedFrame(_ pixelBuffer: CVPixelBuffer, frameNumber: UInt, timeAtFirstFrame: TimeInterval, frameDuration: TimeInterval, forceKeyFrame: Bool) throws {
    lock.withLock { keyFrames.append(forceKeyFrame) }
  }
}
