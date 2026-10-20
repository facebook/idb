/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import CoreVideo
import FBControlCore
@testable import FBSimulatorControl
@testable import FBSimulatorVideo
import FBVideoCore
import Foundation
import IOSurface
import ImageIO
import Testing

@Suite
struct SimulatorVideoCaptureOrientationTests {
  private func start(recording: Bool = false) async throws -> SimulatorVideoStream {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = try makeTestIOSurface(width: 20, height: 30) { x, y in
      (b: UInt8(x * 10), g: UInt8(y * 8), r: 0, a: 255)
    }
    let stream = SimulatorVideoStream(
      framebuffer: Framebuffer(surface: surface, logger: CapturingLogger()),
      configuration: VideoStreamConfiguration(format: .bgra, framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil),
      edgeInsets: VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), cadence: .lazy,
      logger: CapturingLogger(), encodedSampleConsumerOverride: recording ? DiscardingEncodedSampleConsumer() : nil)
    try await stream.startStreaming(AccumulatingBuffer())
    return stream
  }

  private func image(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  @Test
  func aHalfTurnChangesRecordingAndScreenshotPixelsWithoutChangingTheCanvas() async throws {
    let stream = try await start(recording: true)
    let before = try await stream.captureCompositedScreenshot()
    await stream.applyCaptureRotation(.upsideDown)
    let after = try await stream.captureCompositedScreenshot()
    let beforeImage = try image(before)
    let afterImage = try image(after)
    #expect(await stream.captureRotation == .upsideDown)
    #expect(beforeImage.width == afterImage.width && beforeImage.height == afterImage.height)
    #expect(before != after, "A half-turn must change the rendered pixels")
    try await stream.stopStreaming()
  }

  @Test
  func oppositeQuarterTurnsChangePixelsAtTheSameDimensions() async throws {
    let stream = try await start()
    await stream.applyCaptureRotation(.clockwise)
    let before = try await stream.captureCompositedScreenshot()
    await stream.applyCaptureRotation(.counterclockwise)
    let after = try await stream.captureCompositedScreenshot()
    let beforeImage = try image(before)
    let afterImage = try image(after)
    #expect(await stream.captureRotation == .counterclockwise)
    #expect(beforeImage.width == 30 && beforeImage.height == 20)
    #expect(afterImage.width == 30 && afterImage.height == 20)
    #expect(before != after)
    try await stream.stopStreaming()
  }
}

extension SimulatorVideoStream {
  fileprivate var captureRotation: SimulatorDisplayRotation { compositor.rotation }

  fileprivate func applyCaptureRotation(_ rotation: SimulatorDisplayRotation) {
    let display = SimulatorDisplay(
      uniqueID: "panel", name: "panel", activity: .active, isPrimary: true, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: 20, height: 30), scale: 2, rotation: rotation)
    displayConfiguration = SimulatorDisplayConfiguration(generation: 1, displays: [display], active: .identified(display), phase: .settled)
    reconcileMount()
  }
}
