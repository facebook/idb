/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import FBVideoCore
import Foundation
import Testing

@Suite
struct SimulatorFramebufferCommandsTests {

  private static func display(_ id: String) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: id, activity: .active, isPrimary: false,
      isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: .upright)
  }

  private func framebuffer(
    _ display: DisplaySelection,
    displays: any DisplayCommands = DisplayCommandsDouble(.selected(display("inner"))),
    screens: FramebufferScreensDouble
  ) async throws -> FramebufferAttachment {
    try await SimulatorFramebufferCommands.framebuffer(display: display, displays: displays, screens: screens, logger: CapturingLogger()).attach()
  }

  @Test
  func theMainDisplayCapturesTheMainScreen() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.main, screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == [])
    #expect(screens.main.registeredTokens.count == 1)
  }

  @Test
  func aNamedDisplayCapturesItsScreen() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.display(uniqueID: "inner"), screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == ["inner"])
    #expect(screens.screens["inner"]?.registeredTokens.count == 1)
    #expect(screens.screens["cover"]?.registeredTokens.count == 0)
    #expect(screens.main.registeredTokens.count == 0)
  }

  @Test
  func aNamedDisplayAnnouncesTheConfiguration() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.display(uniqueID: "cover"), screens: screens)
    defer { attachment.cancel() }

    let configuration = await firstConfiguration(of: attachment)
    #expect(configuration?.active == .identified(Self.display("inner")))
    #expect(screens.screens["inner"]?.registeredTokens.count == 0)
  }

  @Test
  func theActiveDisplayOfASoleDisplayAnnouncesTheConfiguration() async throws {
    let screens = FramebufferScreensDouble("lcd")
    let attachment = try await framebuffer(.active, displays: DisplayCommandsDouble(.sole(.identified(Self.display("lcd")))), screens: screens)
    defer { attachment.cancel() }

    let configuration = await firstConfiguration(of: attachment)
    #expect(configuration?.active == .identified(Self.display("lcd")))
  }

  @Test
  func aNamedDisplayIsCapturedWhileAnotherIsActive() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.display(uniqueID: "cover"), screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == ["cover"])
    #expect(screens.screens["cover"]?.registeredTokens.count == 1)
    #expect(screens.screens["inner"]?.registeredTokens.count == 0)
    #expect(screens.main.registeredTokens.count == 0)
  }

  @Test
  func aNamedDisplayWithNoScreenFails() async throws {
    let screens = FramebufferScreensDouble("cover")
    do {
      _ = try await framebuffer(.display(uniqueID: "inner"), screens: screens)
      Issue.record("Expected a named display with no screen to fail")
    } catch is FramebufferScreensDouble.NoScreen {}
    #expect(screens.main.registeredTokens.count == 0)
  }

  @Test
  func theActiveDisplayCapturesTheActiveOneOfSeveralScreens() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.active, screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == ["inner"])
    #expect(screens.screens["inner"]?.registeredTokens.count == 1)
    #expect(screens.main.registeredTokens.count == 0)
    let configuration = await firstConfiguration(of: attachment)
    #expect(configuration?.active == .identified(Self.display("inner")))
  }

  @Test
  func theActiveDisplayOfASoleDisplayCapturesTheMainScreen() async throws {
    let screens = FramebufferScreensDouble("lcd")
    let attachment = try await framebuffer(.active, displays: DisplayCommandsDouble(.sole(.identified(Self.display("lcd")))), screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == [])
    #expect(screens.main.registeredTokens.count == 1)
  }

  @Test
  func theActiveDisplayCapturesTheMainScreenWhenTheDisplaysCannotBeRead() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.active, displays: DisplayCommandsDouble([.success(.failed(.malformed("unreadable")))]), screens: screens)
    defer { attachment.cancel() }

    #expect(screens.main.registeredTokens.count == 1)
  }

  @Test
  func theActiveDisplayCapturesTheMainScreenWhenItHasNoScreen() async throws {
    let screens = FramebufferScreensDouble("cover")
    let attachment = try await framebuffer(.active, screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == ["inner"])
    #expect(screens.main.registeredTokens.count == 1)
  }

  @Test
  func aConfigurationCapturesItsActiveDisplay() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(.configuration(generation: 1), screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == ["inner"])
    #expect(screens.screens["inner"]?.registeredTokens.count == 1)
    #expect(screens.main.registeredTokens.count == 0)
  }

  @Test
  func aConfigurationEndsOnceItIsReplaced() async throws {
    let (pushes, push) = AsyncThrowingStream<SimulatorDisplayReport, any Error>.makeStream()
    let displays = DisplayCommandsDouble([.success(.reporting(.selected(Self.display("inner"))))], pushes: pushes)
    let attachment = try await framebuffer(.configuration(generation: 1), displays: displays, screens: FramebufferScreensDouble("cover", "inner"))
    defer { attachment.cancel() }

    var events: [FramebufferEvent] = []
    for await event in attachment.events {
      events.append(event)
      if events.count == 1 { push.yield(.reporting(.selected(Self.display("cover")))) }
    }
    guard events.count == 3, case let .configurationChanged(replacement) = events[1], case .ended(.changed) = events[2] else {
      Issue.record("Unexpected events \(events)")
      return
    }
    #expect(replacement.active == .identified(Self.display("cover")))
  }

  @Test
  func aReplacedConfigurationIsNotCaptured() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    do {
      _ = try await framebuffer(.configuration(generation: 2), screens: screens)
      Issue.record("Expected a replaced configuration to fail")
    } catch SimulatorDisplayError.changed {}
    #expect(screens.requested == [])
  }

  @Test
  func theDisplayAVideoCapturesByDefault() async throws {
    let configuration = VideoStreamConfiguration(
      format: VideoStreamFormat.compressedVideo(withCodec: VideoStreamCodec.h264, transport: VideoStreamTransport.annexB),
      framesPerSecond: nil, rateControl: nil, scaleFactor: nil, keyFrameRate: nil)
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(configuration.display, screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == ["inner"])
    #expect(screens.screens["inner"]?.registeredTokens.count == 1)
    #expect(screens.main.registeredTokens.count == 0)
  }

  @Test
  func theDisplayAFramebufferCapturesByDefault() async throws {
    let screens = FramebufferScreensDouble("cover", "inner")
    let attachment = try await framebuffer(SimulatorFramebufferCommands.defaultDisplay, screens: screens)
    defer { attachment.cancel() }

    #expect(screens.requested == ["inner"])
    #expect(screens.screens["inner"]?.registeredTokens.count == 1)
    #expect(screens.main.registeredTokens.count == 0)
  }

  private func firstConfiguration(of attachment: FramebufferAttachment) async -> SimulatorDisplayConfiguration? {
    for await event in attachment.events {
      if case let .configurationChanged(configuration) = event { return configuration }
    }
    return nil
  }
}
