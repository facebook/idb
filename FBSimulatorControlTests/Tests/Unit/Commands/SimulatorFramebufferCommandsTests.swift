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

  private static func display(_ id: String) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: id, activity: .active, isPrimary: false,
      isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: .upright)
  }

  private func framebuffer(
    _ display: FramebufferDisplay,
    displays: any DisplayCommands = DisplayCommandsDouble(.selected(display("inner"))),
    screens: FramebufferScreensDouble
  ) async throws -> FramebufferAttachment {
    try await SimulatorFramebufferCommands.framebuffer(display: display, displays: displays, screens: screens, logger: CapturingLogger()).attach()
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

  func testANamedDisplayAnnouncesTheConfiguration() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.display(uniqueID: "cover"), screens: screens)
    defer { attachment.cancel() }

    let configuration = await firstConfiguration(of: attachment)
    XCTAssertEqual(configuration?.active, .identified(Self.display("inner")))
    XCTAssertEqual(screens.screens["inner"]?.registeredTokens.count, 0)
  }

  func testTheActiveDisplayOfASoleDisplayAnnouncesTheConfiguration() async throws {
    let screens = FramebufferScreensDouble("lcd")
    let attachment = try await framebuffer(.active, displays: DisplayCommandsDouble(.sole(.identified(Self.display("lcd")))), screens: screens)
    defer { attachment.cancel() }

    let configuration = await firstConfiguration(of: attachment)
    XCTAssertEqual(configuration?.active, .identified(Self.display("lcd")))
  }

  func testANamedDisplayIsCapturedWhileAnotherIsActive() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.display(uniqueID: "cover"), screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.requested, ["cover"])
    XCTAssertEqual(screens.screens["cover"]?.registeredTokens.count, 1)
    XCTAssertEqual(screens.screens["inner"]?.registeredTokens.count, 0)
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

  func testTheActiveDisplayCapturesTheActiveOneOfSeveralScreens() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.active, screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.requested, ["inner"])
    XCTAssertEqual(screens.screens["inner"]?.registeredTokens.count, 1)
    XCTAssertEqual(screens.main.registeredTokens.count, 0)
    let configuration = await firstConfiguration(of: attachment)
    XCTAssertEqual(configuration?.active, .identified(Self.display("inner")))
  }

  func testTheActiveDisplayOfASoleDisplayCapturesTheMainScreen() async throws {
    let screens = FramebufferScreensDouble("lcd")
    let attachment = try await framebuffer(.active, displays: DisplayCommandsDouble(.sole(.identified(Self.display("lcd")))), screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.requested, [])
    XCTAssertEqual(screens.main.registeredTokens.count, 1)
  }

  func testTheActiveDisplayCapturesTheMainScreenWhenTheDisplaysCannotBeRead() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.active, displays: DisplayCommandsDouble([.success(.failed(.malformed("unreadable")))]), screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.main.registeredTokens.count, 1)
  }

  func testTheActiveDisplayCapturesTheMainScreenWhenItHasNoScreen() async throws {
    let screens = FramebufferScreensDouble("cover")
    let attachment = try await framebuffer(.active, screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.requested, ["inner"])
    XCTAssertEqual(screens.main.registeredTokens.count, 1)
  }

  func testTheDisplayAVideoCapturesByDefault() async throws {
    let configuration = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: VideoStreamCodec.h264, transport: VideoStreamTransport.annexB),
      framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(configuration.display, screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.requested, ["inner"])
    XCTAssertEqual(screens.screens["inner"]?.registeredTokens.count, 1)
    XCTAssertEqual(screens.main.registeredTokens.count, 0)
  }

  func testTheDisplayAFramebufferCapturesByDefault() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(SimulatorFramebufferCommands.defaultDisplay, screens: screens)
    defer { attachment.cancel() }

    XCTAssertEqual(screens.requested, ["inner"])
    XCTAssertEqual(screens.screens["inner"]?.registeredTokens.count, 1)
    XCTAssertEqual(screens.main.registeredTokens.count, 0)
  }

  private func firstConfiguration(of attachment: FramebufferAttachment) async -> SimulatorDisplayConfiguration? {
    for await event in attachment.events {
      if case let .configurationChanged(configuration) = event { return configuration }
    }
    return nil
  }
}
