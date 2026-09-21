/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
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
    try SimulatorHingeAngle.requireSupportedModel(simulator.device.deviceType?.modelIdentifier)
    let version = try SimulatorHingeProtocol.installedVersion()
    let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.hinge-read")
    let transport = try SimulatorHingeReadTransport(simulator: simulator, queue: queue)
    let session = SimulatorHingeReadSession(transport: transport, queue: queue)
    return try await session.read(deviceID: simulator.udid, version: version)
  }
}
