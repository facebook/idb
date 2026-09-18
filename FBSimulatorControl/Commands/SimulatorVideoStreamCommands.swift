/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorVideoStreamCommands: VideoStreamCommands {
  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> SimulatorVideoStreamCommands {
    SimulatorVideoStreamCommands(simulator: simulator)
  }

  init(simulator: Simulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  public func create(configuration: VideoStreamConfiguration, to consumer: any DataConsumer) async throws -> any VideoStreamOperation {
    let framebuffer = try await simulator.lifecycle.connectToFramebuffer()
    return try await SimulatorVideoStream.start(framebuffer: framebuffer, configuration: configuration, to: consumer, logger: simulator.logger)
  }
}
