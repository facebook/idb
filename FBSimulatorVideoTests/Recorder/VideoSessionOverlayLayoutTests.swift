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

/// How a recording session's overlays and bars are laid out when the stream's canvas changes.
@MainActor
final class VideoSessionOverlayLayoutTests: XCTestCase {

  private struct Session {
    let stream: SimulatorVideoStream
    let surface: FakeFramebufferSurface
    let renderer: OverlayRenderer
    let handler: StdinCommandHandler
  }

  private func startSession() async throws -> Session {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface(width: 20, height: 30)
    let stream = SimulatorVideoStream(
      framebuffer: Framebuffer(surface: surface, logger: CapturingLogger()),
      configuration: VideoStreamConfiguration(format: .bgra, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil),
      edgeInsets: VideoStreamEdgeInsets(top: 4, bottom: 4, left: 0, right: 0),
      cadence: .lazy,
      logger: CapturingLogger())
    try await stream.startStreaming(FBDataBuffer.accumulatingBuffer())
    let renderer = OverlayRenderer(
      transform: OverlayCoordinateTransform(
        screenPixelWidth: 20, screenPixelHeight: 30, retinaScale: 1, videoScale: 1, borderTop: 4, scaledBorderTop: 4, borderBottom: 4,
        scaledBorderBottom: 4))
    let (handler, _) = VideoSession.makeHandler(
      videoStream: stream, renderer: renderer, screenshotDir: nil, parsedBars: [(position: "top", height: 4, mode: .pad)], barStats: [],
      logger: CapturingLogger())
    renderer.setBarContent(.text("bar"), position: "top")
    await stream.updateOverlayBuffer(renderer.buffer)
    return Session(stream: stream, surface: surface, renderer: renderer, handler: handler)
  }

  private func display(width: Int, height: Int, rotation: SimulatorDisplayRotation) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: "panel", name: "panel", activity: .active, isPrimary: true, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: width, height: height), scale: 1, rotation: rotation)
  }

  private func waitUntil(_ condition: @escaping () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
    let deadline = Date(timeIntervalSinceNow: 5)
    while await !condition() {
      guard deadline.timeIntervalSinceNow > 0 else { return XCTFail("condition never held", file: file, line: line) }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  private func size(_ buffer: CVPixelBuffer?) -> CGSize? {
    buffer.map { CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0)) }
  }

  func testTheOverlayAfterASwitchToALargerSurface() async throws {
    let session = try await startSession()
    session.surface.ioSurfaceChanged?(makeTestIOSurface(width: 40, height: 60))
    try await waitUntil { await session.stream.mountedSource?.width == 40 }

    let composited = await size(session.stream.compositor.overlayBuffer)
    XCTAssertEqual(size(session.renderer.buffer), CGSize(width: 40, height: 68))
    XCTAssertEqual(composited, CGSize(width: 40, height: 68))
    try await session.stream.stopStreaming()
  }

  func testTheOverlayAfterARotation() async throws {
    let session = try await startSession()
    let turned = display(width: 20, height: 30, rotation: .clockwise)
    session.surface.configurationChanged?(SimulatorDisplayConfiguration(generation: 1, displays: [turned], active: .identified(turned), phase: .settled))
    try await waitUntil { await session.stream.mountedSource?.width == 30 }

    let composited = await size(session.stream.compositor.overlayBuffer)
    XCTAssertEqual(size(session.renderer.buffer), CGSize(width: 30, height: 28))
    XCTAssertEqual(composited, CGSize(width: 30, height: 28))
    try await session.stream.stopStreaming()
  }
}
