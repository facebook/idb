/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
import FBControlCore
@testable import FBSimulatorVideo
import FBVideoCore
import XCTest

final class FramePusherPoolTests: XCTestCase {
  private let size = FramePusherPool.Source(width: 1398, height: 2034, pixelFormat: kCVPixelFormatType_32BGRA)

  func testAKeptPusherIsTakenOnce() {
    var pool = FramePusherPool()
    let pusher = BitmapFramePusher(consumer: FBDataBuffer.accumulatingBuffer(), scaleFactor: nil)
    XCTAssertNil(pool.keep(pusher, for: size))
    XCTAssertTrue(pool.contains(size))
    XCTAssertTrue(pool.take(size) === pusher)
    XCTAssertNil(pool.take(size))
  }

  func testKeepingASecondPusherForASourceReturnsTheFirst() {
    var pool = FramePusherPool()
    let first = BitmapFramePusher(consumer: FBDataBuffer.accumulatingBuffer(), scaleFactor: nil)
    let second = BitmapFramePusher(consumer: FBDataBuffer.accumulatingBuffer(), scaleFactor: nil)
    _ = pool.keep(first, for: size)
    XCTAssertTrue(pool.keep(second, for: size) === first)
    XCTAssertTrue(pool.take(size) === second)
  }

  func testRemovingAllEmptiesThePool() {
    var pool = FramePusherPool()
    _ = pool.keep(BitmapFramePusher(consumer: FBDataBuffer.accumulatingBuffer(), scaleFactor: nil), for: size)
    _ = pool.keep(BitmapFramePusher(consumer: FBDataBuffer.accumulatingBuffer(), scaleFactor: nil), for: FramePusherPool.Source(width: 2007, height: 2853, pixelFormat: kCVPixelFormatType_32BGRA))
    XCTAssertEqual(pool.removeAll().count, 2)
    XCTAssertFalse(pool.contains(size))
  }

  func testASourceIsAPositiveWholeNumberOfPixels() {
    let bgra = kCVPixelFormatType_32BGRA
    XCTAssertEqual(FramePusherPool.Source(CGSize(width: 2007, height: 2853), pixelFormat: bgra), FramePusherPool.Source(width: 2007, height: 2853, pixelFormat: bgra))
    XCTAssertNil(FramePusherPool.Source(CGSize(width: 2007.5, height: 2853), pixelFormat: bgra))
    XCTAssertNil(FramePusherPool.Source(CGSize(width: 0, height: 2853), pixelFormat: bgra))
  }

  func testAPusherIsTakenOnlyForItsPixelFormat() {
    var pool = FramePusherPool()
    _ = pool.keep(BitmapFramePusher(consumer: FBDataBuffer.accumulatingBuffer(), scaleFactor: nil), for: size)
    XCTAssertNil(pool.take(FramePusherPool.Source(width: size.width, height: size.height, pixelFormat: kCVPixelFormatType_32RGBA)))
    XCTAssertNotNil(pool.take(size))
  }

  func testWarmingAVideoToolboxPusherHandsNothingOn() throws {
    try VideoEncodingHostSupport.skipUnlessHardwareH264Encoding()
    let pusher = createTestVideoStreamPusher(CapturingLogger())
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
    XCTAssertEqual(CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer), kCVReturnSuccess)
    let pixelBuffer = try XCTUnwrap(buffer)
    try pusher.setup(with: pixelBuffer, edgeInsets: VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0))
    defer { try? pusher.tearDown() }

    try pusher.warm(with: pixelBuffer)

    XCTAssertEqual(pusher.statsRecorder.snapshot.callbackCount, 0)
  }
}
