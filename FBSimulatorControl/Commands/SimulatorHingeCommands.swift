/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public struct SimulatorHingeCommands {
  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> SimulatorHingeCommands {
    SimulatorHingeCommands(simulator: simulator)
  }

  public func setAngle(_ angle: SimulatorHingeAngle) async throws {
    try await simulator.sendHIDGesture(.hinge(angle))
  }

  /// Reads a fresh measured angle. During a hinge animation this can be between its endpoints.
  public func angle() async throws -> SimulatorHingeAngle {
    try await MotionCapabilities.resolve(on: simulator).require(.hingeAngle)
    let channel = UUID()
    // Samples older than the request are the provider replaying its last known state.
    let notBefore = ProcessInfo.processInfo.systemUptime
    return try await simulator.coreDevice.stream(
      action: SimulatorHingeProtocol.action, service: SimulatorHingeProtocol.service,
      input: SimulatorHingeProtocol.StreamInput(channel: channel)
    ) { event in
      try SimulatorHingeProtocol.sample(event, channel: channel, notBefore: notBefore, now: ProcessInfo.processInfo.systemUptime)
    }
  }
}
