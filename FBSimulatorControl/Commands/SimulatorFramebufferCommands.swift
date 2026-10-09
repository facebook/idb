/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The display surfaces a framebuffer can capture. `SimulatorFramebufferScreens` finds them among the
/// simulator's IO ports.
protocol FramebufferScreens: Sendable {
  func mainScreen() throws -> any FramebufferSurface

  /// The screen of the display with this CoreDevice UUID.
  func screen(uniqueID: String) async throws -> any FramebufferSurface
}

struct SimulatorFramebufferScreens: FramebufferScreens {
  let simulator: Simulator

  func mainScreen() throws -> any FramebufferSurface {
    try FramebufferSurfaceLocator.mainDisplaySurface(for: simulator, logger: simulator.logger)
  }

  func screen(uniqueID: String) async throws -> any FramebufferSurface {
    try await FramebufferSurfaceLocator.surface(uniqueID: uniqueID, simulator: simulator)
  }
}

/// Connects to the simulator's framebuffers.
public struct SimulatorFramebufferCommands: Sendable {

  private let simulator: Simulator

  init(simulator: Simulator) {
    self.simulator = simulator
  }

  @usableFromInline static let defaultDisplay: DisplaySelection = .active

  /// A framebuffer for `display`. Each call connects anew; callers that need one connection across
  /// several operations hold on to the result. Framebuffers for several displays can be connected at once,
  /// such as one per display to switch between them without waiting to connect.
  public func connect(display: DisplaySelection = defaultDisplay) async throws -> Framebuffer {
    try await Self.framebuffer(display: display, displays: simulator.displays, screens: SimulatorFramebufferScreens(simulator: simulator), logger: simulator.logger)
  }

  /// As for screenshots, the active display improves on the main screen but is never required. A sole
  /// display is the main screen, so only a simulator with several integrated displays follows one. A named
  /// display is required: capturing another in its place would capture something the caller did not ask for.
  /// A configuration is required too, and its framebuffer ends once the configuration is replaced. Every
  /// framebuffer but the main screen's follows the display configuration, to report it.
  static func framebuffer(display: DisplaySelection, displays: any DisplayCommands, screens: any FramebufferScreens, logger: any ControlCoreLogger) async throws -> Framebuffer {
    switch display {
    case .main:
      return Framebuffer(surface: try screens.mainScreen(), logger: logger)
    case .active:
      return Framebuffer(surface: try await activeScreen(displays: displays, screens: screens, logger: logger), logger: logger)
    case let .display(uniqueID):
      let surface = FollowingFramebufferSurface(
        displayUniqueID: uniqueID, surface: try await screens.screen(uniqueID: uniqueID), movement: .fixed,
        configurations: { displays.followConfigurations() }, locate: { try await screens.screen(uniqueID: $0) }, logger: logger)
      return Framebuffer(surface: surface, logger: logger)
    case let .configuration(generation):
      let active = try await displays.activeDisplay(selectedBy: display, within: displays.transitionSettling.timeout)
      let surface = FollowingFramebufferSurface(
        displayUniqueID: active.uniqueID, surface: try await screens.screen(uniqueID: active.uniqueID), movement: .fixed,
        configurations: { displays.followConfigurations() }, locate: { try await screens.screen(uniqueID: $0) }, logger: logger)
      return Framebuffer(surface: surface, boundTo: generation, logger: logger)
    }
  }

  private static func activeScreen(displays: any DisplayCommands, screens: any FramebufferScreens, logger: any ControlCoreLogger) async throws -> any FramebufferSurface {
    do {
      switch try await displays.resolveDisplay() {
      case let .target(.selected(display)):
        return FollowingFramebufferSurface(
          displayUniqueID: display.uniqueID, surface: try await screens.screen(uniqueID: display.uniqueID), movement: .followsActiveDisplay,
          configurations: { displays.followConfigurations() }, locate: { try await screens.screen(uniqueID: $0) }, logger: logger)
      case let .target(.sole(display)):
        return FollowingFramebufferSurface(
          displayUniqueID: display.uniqueID, surface: try screens.mainScreen(), movement: .fixed,
          configurations: { displays.followConfigurations() }, locate: { try await screens.screen(uniqueID: $0) }, logger: logger)
      case let resolution:
        logger.log("Capturing the main screen, as no active display is identified: \(resolution)")
      }
    } catch let error as CancellationError {
      throw error
    } catch {
      logger.log("Capturing the main screen, as the active display could not be captured: \(error)")
    }
    return try screens.mainScreen()
  }
}
