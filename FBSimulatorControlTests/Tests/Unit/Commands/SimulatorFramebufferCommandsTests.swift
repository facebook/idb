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

final class SimulatorFramebufferCommandsTests: XCTestCase {

  private func framebuffer(_ display: FramebufferDisplay, screens: FramebufferScreensDouble) async throws -> FramebufferAttachment {
    try await SimulatorFramebufferCommands.framebuffer(display: display, screens: screens, logger: CapturingLogger()).attach()
  }

  func testTheMainDisplayCapturesTheMainScreen() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.main, screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.requested, [])
    XCTAssertEqual(screens.main.registeredTokens.count, 1)
  }

  func testANamedDisplayCapturesItsScreen() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.display(uniqueID: "inner"), screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.requested, ["inner"])
    XCTAssertEqual(screens.screens["inner"]?.registeredTokens.count, 1)
    XCTAssertEqual(screens.screens["cover"]?.registeredTokens.count, 0)
    XCTAssertEqual(screens.main.registeredTokens.count, 0)
  }

  func testANamedDisplayWithNoScreenFails() async throws {
    let screens = FramebufferScreensDouble("cover")
    do {
      _ = try await framebuffer(.display(uniqueID: "inner"), screens: screens)
      XCTFail("Expected a named display with no screen to fail")
    } catch is FramebufferScreensDouble.NoScreen {}
    XCTAssertEqual(screens.main.registeredTokens.count, 0)
  }
}
