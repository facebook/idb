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

  /// `image()` lazily attaches its generator to the framebuffer on first use and must not re-attach
  /// on later calls. The attach is serialized on the image's private queue; the concurrent
  /// double-attach that serialization guards against is not deterministically unit-testable, so this
  /// pins the serial attach-exactly-once invariant.
  func testImageAttachesGeneratorExactlyOnce() {
    let surface = FakeFramebufferSurface()
    surface.immediateSurface = makeTestIOSurface()
    let framebuffer = FBFramebuffer(surface: surface, logger: FBCapturingLogger())
    let image = FBSimulatorImage(framebuffer: framebuffer, logger: FBCapturingLogger())

    _ = image.image()
    _ = image.image()
    _ = image.image()

    XCTAssertEqual(surface.registeredTokens.count, 1)
  }
}
