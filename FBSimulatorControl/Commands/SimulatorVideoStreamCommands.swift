/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct SimulatorVideoStreamCommands {
  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> SimulatorVideoStreamCommands {
    SimulatorVideoStreamCommands(simulator: simulator)
  }

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    let framebuffer = try await simulator.lifecycle.connectToFramebuffer()
    return try await FBSimulatorVideoStream.start(framebuffer: framebuffer, configuration: configuration, to: consumer, logger: simulator.logger)
  }
}

// MARK: - FBSimulator+VideoStreamCommands

extension FBSimulator: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    try await videoStream.createStream(configuration: configuration, to: consumer)
  }
}
