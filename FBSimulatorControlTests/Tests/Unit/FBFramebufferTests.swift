/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import IOSurface
import XCTest

final class FBFramebufferTests: XCTestCase {

  // MARK: - Helpers

  private func makeFramebuffer(surface: FakeFramebufferSurface) -> FBFramebuffer {
    FBFramebuffer(surface: surface, logger: FBCapturingLogger())
  }

  private func makeQueue() -> DispatchQueue {
    DispatchQueue(label: "com.facebook.FBSimulatorControl.tests.framebuffer")
  }

  // MARK: - Attach

  func testAttachReturnsImmediatelyAvailableSurface() throws {
    let surface = FakeFramebufferSurface()
    let ioSurface = makeTestIOSurface()
    surface.immediateSurface = ioSurface
    let framebuffer = makeFramebuffer(surface: surface)

    let attachment = try framebuffer.attach(FakeFramebufferConsumer(), on: makeQueue())

    XCTAssertIdentical(attachment.initialSurface, ioSurface)
  }

  func testAttachReturnsNilWhenNoSurfaceAvailable() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)

    let attachment = try framebuffer.attach(FakeFramebufferConsumer(), on: makeQueue())

    XCTAssertNil(attachment.initialSurface)
  }

  func testAttachThrowsWhenRegistrationFails() {
    let surface = FakeFramebufferSurface()
    surface.registerError = FBFramebufferError.surfaceCallbackRegistrationFailed(underlying: nil)
    let framebuffer = makeFramebuffer(surface: surface)

    XCTAssertThrowsError(try framebuffer.attach(FakeFramebufferConsumer(), on: makeQueue()))
  }

  // MARK: - Consumer fan-out

  func testIOSurfaceChangeDeliveredToConsumer() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let consumer = FakeFramebufferConsumer()
    let queue = makeQueue()
    let attachment = try framebuffer.attach(consumer, on: queue)
    defer { attachment.cancel() }

    let delivered = expectation(description: "surface delivered on the consumer queue")
    consumer.onSurface = { delivered.fulfill() }
    let ioSurface = makeTestIOSurface()
    surface.ioSurfaceChanged?(ioSurface)

    wait(for: [delivered], timeout: 5)
    XCTAssertEqual(consumer.receivedSurfaces.count, 1)
    XCTAssertIdentical(consumer.receivedSurfaces.first ?? nil, ioSurface)
  }

  func testFrameRenderedDeliveredToConsumer() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let consumer = FakeFramebufferConsumer()
    let queue = makeQueue()
    let attachment = try framebuffer.attach(consumer, on: queue)
    defer { attachment.cancel() }

    let delivered = expectation(description: "frame-rendered delivered on the consumer queue")
    consumer.onFrameRendered = { delivered.fulfill() }
    surface.frameRendered?()

    wait(for: [delivered], timeout: 5)
    XCTAssertEqual(consumer.frameRenderedCount, 1)
  }

  // MARK: - Stats

  func testStatsCountCallbacks() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let queue = makeQueue()
    _ = try framebuffer.attach(FakeFramebufferConsumer(), on: queue)

    surface.ioSurfaceChanged?(makeTestIOSurface())
    surface.ioSurfaceChanged?(makeTestIOSurface())
    surface.frameRendered?()
    surface.frameRendered?()
    queue.sync {}

    let stats = framebuffer.currentStats()
    XCTAssertEqual(stats.ioSurfaceChangeCount, 2)
    XCTAssertEqual(stats.frameRenderedCount, 2)
  }

  func testStatsStartTimeSetAfterFirstFrame() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let queue = makeQueue()
    _ = try framebuffer.attach(FakeFramebufferConsumer(), on: queue)

    XCTAssertEqual(framebuffer.statsStartTime, 0)

    surface.frameRendered?()
    queue.sync {}

    XCTAssertGreaterThan(framebuffer.statsStartTime, 0)
  }

  // MARK: - Attachment lifecycle

  func testAttachmentCancelUnregistersCallbacks() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let attachment = try framebuffer.attach(FakeFramebufferConsumer(), on: makeQueue())

    attachment.cancel()

    XCTAssertEqual(surface.unregisteredTokens.count, 1)
  }

  func testAttachmentCancelIsIdempotent() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let attachment = try framebuffer.attach(FakeFramebufferConsumer(), on: makeQueue())

    attachment.cancel()
    attachment.cancel()

    XCTAssertEqual(surface.unregisteredTokens.count, 1)
  }

  func testAttachmentReleaseUnregisters() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)

    do {
      _ = try framebuffer.attach(FakeFramebufferConsumer(), on: makeQueue())
    }

    XCTAssertEqual(surface.unregisteredTokens.count, 1)
  }
}
