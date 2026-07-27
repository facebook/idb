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

  func testAttachReturnsImmediatelyAvailableSurface() {
    let surface = FakeFramebufferSurface()
    let ioSurface = makeTestIOSurface()
    surface.immediateSurface = ioSurface
    let framebuffer = makeFramebuffer(surface: surface)

    let returned = framebuffer.attach(FakeFramebufferConsumer(), on: makeQueue())

    XCTAssertIdentical(returned, ioSurface)
  }

  func testAttachReturnsNilWhenNoSurfaceAvailable() {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)

    let returned = framebuffer.attach(FakeFramebufferConsumer(), on: makeQueue())

    XCTAssertNil(returned)
  }

  // MARK: - Consumer fan-out

  func testIOSurfaceChangeDeliveredToConsumer() {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let consumer = FakeFramebufferConsumer()
    let queue = makeQueue()
    _ = framebuffer.attach(consumer, on: queue)

    let ioSurface = makeTestIOSurface()
    surface.ioSurfaceChanged?(ioSurface)
    queue.sync {}

    XCTAssertEqual(consumer.receivedSurfaces.count, 1)
    XCTAssertIdentical(consumer.receivedSurfaces.first ?? nil, ioSurface)
  }

  func testDamageDeliveredToConsumer() {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let consumer = FakeFramebufferConsumer()
    let queue = makeQueue()
    _ = framebuffer.attach(consumer, on: queue)

    surface.damageReceived?(FBFramebufferDamage(rects: [CGRect(x: 0, y: 0, width: 1, height: 1)]))
    queue.sync {}

    XCTAssertEqual(consumer.damageCallbackCount, 1)
  }

  func testEmptyDamageStillPingsConsumer() {
    // Variable-frame-rate (lazy) streaming relies on the damage ping firing even when no rects are
    // reported, so an empty damage batch must still reach the consumer.
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let consumer = FakeFramebufferConsumer()
    let queue = makeQueue()
    _ = framebuffer.attach(consumer, on: queue)

    surface.damageReceived?(FBFramebufferDamage(rects: []))
    queue.sync {}

    XCTAssertEqual(consumer.damageCallbackCount, 1)
  }

  // MARK: - Stats

  func testStatsCountCallbacks() {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let queue = makeQueue()
    _ = framebuffer.attach(FakeFramebufferConsumer(), on: queue)

    surface.ioSurfaceChanged?(makeTestIOSurface())
    surface.ioSurfaceChanged?(makeTestIOSurface())
    surface.damageReceived?(FBFramebufferDamage(rects: [CGRect(x: 0, y: 0, width: 2, height: 2), CGRect(x: 1, y: 1, width: 3, height: 3)]))
    surface.damageReceived?(FBFramebufferDamage(rects: []))
    queue.sync {}

    let stats = framebuffer.currentStats()
    XCTAssertEqual(stats.ioSurfaceChangeCount, 2)
    XCTAssertEqual(stats.damageCallbackCount, 2)
    XCTAssertEqual(stats.damageRectCount, 2)
    XCTAssertEqual(stats.emptyDamageCallbackCount, 1)
  }

  func testStatsStartTimeSetAfterFirstDamage() {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let queue = makeQueue()
    _ = framebuffer.attach(FakeFramebufferConsumer(), on: queue)

    XCTAssertEqual(framebuffer.statsStartTime, 0)

    surface.damageReceived?(FBFramebufferDamage(rects: []))
    queue.sync {}

    XCTAssertGreaterThan(framebuffer.statsStartTime, 0)
  }

  // MARK: - Detach

  func testDetachUnregistersCallbacks() {
    let surface = FakeFramebufferSurface()
    let framebuffer = makeFramebuffer(surface: surface)
    let consumer = FakeFramebufferConsumer()
    _ = framebuffer.attach(consumer, on: makeQueue())
    XCTAssertTrue(framebuffer.isConsumerAttached(consumer))

    framebuffer.detach(consumer)

    XCTAssertFalse(framebuffer.isConsumerAttached(consumer))
    XCTAssertEqual(surface.unregisteredTokens.count, 1)
  }
}
