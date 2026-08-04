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

  // MARK: - Event stream

  func testStreamAttachReturnsInitialSurface() throws {
    let surface = FakeFramebufferSurface()
    let ioSurface = makeTestIOSurface()
    surface.immediateSurface = ioSurface
    let framebuffer = makeFramebuffer(surface: surface)

    let attachment = try framebuffer.attach()

    XCTAssertIdentical(attachment.initialSurface, ioSurface)
  }

  func testStreamBuffersAndDeliversEventsInOrder() async throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let attachment = try framebuffer.attach()

    let ioSurface = makeTestIOSurface()
    // All delivered before iteration begins: the stream must buffer without loss, and must preserve
    // the exact order across both event kinds (a surface swap can never overtake a frame).
    surface.ioSurfaceChanged?(ioSurface)
    surface.frameRendered?()
    surface.ioSurfaceChanged?(nil)
    surface.frameRendered?()

    var events: [FBFramebufferEvent] = []
    for await event in attachment.events {
      events.append(event)
      if events.count == 4 {
        break
      }
    }

    guard events.count == 4 else {
      XCTFail("Expected 4 events, got \(events.count)")
      return
    }
    guard case let .surfaceChanged(first) = events[0] else {
      XCTFail("Expected .surfaceChanged first, got \(events[0])")
      return
    }
    XCTAssertIdentical(first, ioSurface)
    guard case .frameRendered = events[1] else {
      XCTFail("Expected .frameRendered second, got \(events[1])")
      return
    }
    guard case let .surfaceChanged(cleared) = events[2] else {
      XCTFail("Expected .surfaceChanged third, got \(events[2])")
      return
    }
    XCTAssertNil(cleared)
    guard case .frameRendered = events[3] else {
      XCTFail("Expected .frameRendered fourth, got \(events[3])")
      return
    }
  }

  func testStreamCancelFinishesIteration() async throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let attachment = try framebuffer.attach()

    surface.frameRendered?()
    attachment.cancel()

    // Buffered events are drained, then the finished stream ends the loop.
    var count = 0
    for await _ in attachment.events {
      count += 1
    }
    XCTAssertEqual(count, 1)
    XCTAssertEqual(surface.unregisteredTokens.count, 1)
  }

  func testStreamAttachRecordsStats() throws {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let attachment = try framebuffer.attach()
    defer { attachment.cancel() }

    surface.ioSurfaceChanged?(makeTestIOSurface())
    surface.frameRendered?()

    let stats = framebuffer.currentStats()
    XCTAssertEqual(stats.ioSurfaceChangeCount, 1)
    XCTAssertEqual(stats.frameRenderedCount, 1)
  }
}
