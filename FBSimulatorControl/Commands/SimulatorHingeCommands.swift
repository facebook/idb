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
    try await SimulatorMotionCapability.hingeAngle.requireSupported(on: simulator)
    let channel = UUID()
    let request = try SimulatorHingeProtocol.request(deviceID: simulator.udid, version: CoreDeviceVersion.installed(), channel: channel)
    let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.hinge-read")
    let transport = try SimulatorCoreDeviceXPCTransport(simulator: simulator, service: SimulatorHingeProtocol.service, queue: queue)
    // Samples older than the request are the provider replaying its last known state.
    let notBefore = ProcessInfo.processInfo.systemUptime
    return try await CoreDeviceSession<SimulatorHingeAngle>(transport: transport, queue: queue).stream(request) { event in
      try SimulatorHingeProtocol.sample(event, channel: channel, notBefore: notBefore, now: ProcessInfo.processInfo.systemUptime)
    }
  }
}
