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

  /// A framebuffer for `display`. Each call connects anew; callers that need one connection across
  /// several operations hold on to the result.
  public func connect(display: FramebufferDisplay = .main) async throws -> Framebuffer {
    try await Self.framebuffer(display: display, screens: SimulatorFramebufferScreens(simulator: simulator), logger: simulator.logger)
  }

  static func framebuffer(display: FramebufferDisplay, screens: any FramebufferScreens, logger: any ControlCoreLogger) async throws -> Framebuffer {
    switch display {
    case .main:
      return Framebuffer(surface: try screens.mainScreen(), logger: logger)
    case let .display(uniqueID):
      return Framebuffer(surface: try await screens.screen(uniqueID: uniqueID), logger: logger)
    }
  }
}
