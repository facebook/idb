/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Connects to the simulator's main screen framebuffer.
public struct SimulatorFramebufferCommands: Sendable {

  private let simulator: Simulator

  init(simulator: Simulator) {
    self.simulator = simulator
  }

  /// A framebuffer for the main screen. Each call connects anew; callers that need one connection
  /// across several operations hold on to the result.
  public func connect() throws -> Framebuffer {
    try Framebuffer.mainScreenSurface(for: simulator, logger: simulator.logger)
  }
}
