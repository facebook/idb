/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

final class FBSimulatorImageTests: XCTestCase {

  /// `image()` lazily attaches to the framebuffer on first use and must not re-attach on later
  /// calls. Actor isolation serializes the attach, so this pins the attach-exactly-once invariant.
  func testImageAttachesGeneratorExactlyOnce() async throws {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface()
    let framebuffer = FBFramebuffer(surface: surface, logger: FBCapturingLogger())
    let image = FBSimulatorImage(framebuffer: framebuffer, logger: FBCapturingLogger())

    _ = try await image.image()
    _ = try await image.image()
    _ = try await image.image()

    XCTAssertEqual(surface.registeredTokens.count, 1)
  }

  /// The image renders from the initial surface seeded at attach time, and keeps rendering after a
  /// surface swap delivered through the event stream.
  func testImageRendersFromInitialAndSwappedSurface() async throws {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface()
    let framebuffer = FBFramebuffer(surface: surface, logger: FBCapturingLogger())
    let image = FBSimulatorImage(framebuffer: framebuffer, logger: FBCapturingLogger())

    let initial = try await image.image()
    XCTAssertNotNil(initial)

    surface.ioSurfaceChanged?(makeTestIOSurface(width: 32, height: 32))
    // The swap propagates through the attachment's event stream onto the actor; poll briefly for the
    // new dimensions rather than racing the delivery task.
    for _ in 0..<100 {
      if let swapped = try await image.image(), swapped.width == 32 {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Image did not pick up the swapped surface")
  }
}
