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
import ImageIO
import XCTest

/// How a stream lays its frames and screenshots out when the interface is rotated on the mounted display.
final class SimulatorVideoStreamOrientationTests: XCTestCase {

  private struct Started {
    let stream: SimulatorVideoStream
    let surface: FakeFramebufferSurface
  }

  private func display(width: Int, height: Int, rotation: SimulatorDisplayRotation) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: "panel", name: "panel", activity: .active, isPrimary: true, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: width, height: height), scale: 2, rotation: rotation)
  }

  private func configuration(_ display: SimulatorDisplay, generation: UInt64 = 1) -> SimulatorDisplayConfiguration {
    SimulatorDisplayConfiguration(generation: generation, displays: [display], active: .identified(display), phase: .settled)
  }

  private func startStream(
    insets: VideoStreamEdgeInsets = VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), recording: Bool = false,
    configurationAtStart: SimulatorDisplayConfiguration? = nil
  ) async throws -> Started {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface(width: 20, height: 30)
    surface.configurationAtRegistration = configurationAtStart
    let stream = SimulatorVideoStream(
      framebuffer: Framebuffer(surface: surface, logger: CapturingLogger()),
      configuration: VideoStreamConfiguration(format: .bgra, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil),
      edgeInsets: insets,
      cadence: .lazy,
      logger: CapturingLogger(),
      encodedSampleConsumerOverride: recording ? DiscardingEncodedSampleConsumer() : nil)
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

  private func pngSize(_ data: Data) throws -> CGSize {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return CGSize(width: image.width, height: image.height)
  }

  func testARotatedInterfaceLaysFramesAndScreenshotsOutInItsOrientation() async throws {
    let started = try await startStream(insets: VideoStreamEdgeInsets(top: 4, bottom: 4, left: 0, right: 0))
    started.surface.configurationChanged?(configuration(display(width: 20, height: 30, rotation: .clockwise)))
    try await waitUntil { await started.stream.displayConfiguration != nil }

    let canvas = await started.stream.canvasSize
    let screenshot = try pngSize(try await started.stream.captureCompositedScreenshot())
    XCTAssertEqual(canvas, CGSize(width: 30, height: 28))
    XCTAssertEqual(screenshot, CGSize(width: 30, height: 20))
    try await started.stream.stopStreaming()
  }

  func testAnUprightInterfaceKeepsThePanelsOrientation() async throws {
    let started = try await startStream(insets: VideoStreamEdgeInsets(top: 4, bottom: 4, left: 0, right: 0))
    started.surface.configurationChanged?(configuration(display(width: 20, height: 30, rotation: .upright)))
    try await waitUntil { await started.stream.displayConfiguration != nil }

    let canvas = await started.stream.canvasSize
    let screenshot = try pngSize(try await started.stream.captureCompositedScreenshot())
    XCTAssertEqual(canvas, CGSize(width: 20, height: 38))
    XCTAssertEqual(screenshot, CGSize(width: 20, height: 30))
    try await started.stream.stopStreaming()
  }

  func testARecordingThroughARotation() async throws {
    let upright = display(width: 20, height: 30, rotation: .upright)
    let started = try await startStream(
      insets: VideoStreamEdgeInsets(top: 4, bottom: 4, left: 0, right: 0), recording: true, configurationAtStart: configuration(upright))
    started.surface.configurationChanged?(configuration(display(width: 20, height: 30, rotation: .clockwise), generation: 2))
    try await waitUntil { await started.stream.mountedSource?.width == 30 }

    let canvas = await started.stream.canvasSize
    let screenshot = try pngSize(try await started.stream.captureCompositedScreenshot())
    // BUG: the recording's canvas follows the rotation, so its file changes frame size mid-recording — flipped in the following commit
    XCTAssertEqual(canvas, CGSize(width: 30, height: 28))
    XCTAssertEqual(screenshot, CGSize(width: 30, height: 20))
    try await started.stream.stopStreaming()
  }

  func testARecordingThroughASwitchToALargerSurface() async throws {
    let upright = display(width: 20, height: 30, rotation: .upright)
    let started = try await startStream(
      insets: VideoStreamEdgeInsets(top: 4, bottom: 4, left: 0, right: 0), recording: true, configurationAtStart: configuration(upright))
    started.surface.ioSurfaceChanged?(makeTestIOSurface(width: 40, height: 60))
    try await waitUntil { await started.stream.mountedSource?.width == 40 }

    let canvas = await started.stream.canvasSize
    let screenshot = try pngSize(try await started.stream.captureCompositedScreenshot())
    // BUG: the recording's canvas follows the larger surface, so its file changes frame size mid-recording — flipped in the following commit
    XCTAssertEqual(canvas, CGSize(width: 40, height: 68))
    XCTAssertEqual(screenshot, CGSize(width: 40, height: 60))
    try await started.stream.stopStreaming()
  }

  func testARecordingStartedInARotatedInterfaceIsInItsOrientation() async throws {
    let turned = display(width: 20, height: 30, rotation: .clockwise)
    let started = try await startStream(
      insets: VideoStreamEdgeInsets(top: 4, bottom: 4, left: 0, right: 0), recording: true, configurationAtStart: configuration(turned))
    try await waitUntil { await started.stream.mountedSource?.width == 30 }

    let canvas = await started.stream.canvasSize
    let screenshot = try pngSize(try await started.stream.captureCompositedScreenshot())
    XCTAssertEqual(canvas, CGSize(width: 30, height: 28))
    XCTAssertEqual(screenshot, CGSize(width: 30, height: 20))
    try await started.stream.stopStreaming()
  }
}

extension SimulatorVideoStream {
  fileprivate var canvasSize: CGSize {
    CGSize(width: compositor.outputWidth, height: compositor.outputHeight)
  }
}
