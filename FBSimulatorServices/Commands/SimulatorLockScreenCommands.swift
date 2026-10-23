/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import FBSimulatorControl
import Foundation

/// SpringBoard's lock state after a lock screen command.
public struct SimulatorLockState: Decodable, Sendable {
  public let locked: Bool
}

public enum SimulatorLockScreenError: Error {
  case undecodableState(output: String, reason: String)
}

extension SimulatorLockScreenError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .undecodableState(output, reason):
      return "Failed to decode the lock state '\(output)': \(reason)"
    }
  }
}

/// Locks and unlocks the simulated device through SpringBoard, without the hardware lock button's toggle.
///
/// `lock` and `unlock` are idempotent and return only once SpringBoard reports the requested state;
/// `unlock` fails on a device with a passcode. iOS only.
public struct SimulatorLockScreenCommands {

  private let simulator: Simulator

  public init(simulator: Simulator) {
    self.simulator = simulator
  }

  public func state() async throws -> SimulatorLockState {
    try await run(.state)
  }

  public func lock() async throws -> SimulatorLockState {
    try await run(.lock)
  }

  public func unlock() async throws -> SimulatorLockState {
    try await run(.unlock)
  }

  private func run(_ command: BridgeCommand.LockScreen) async throws -> SimulatorLockState {
    let output = try await simulator.runSimulatorFrameworkBridge(.lockScreen(command))
    return try SimulatorLockState.decode(bridgeOutput: output)
  }
}

extension SimulatorLockState {
  /// The state is the guest's one JSON value.
  static func decode(bridgeOutput output: String) throws -> SimulatorLockState {
    let line = output.split(separator: "\n").first.map(String.init) ?? ""
    do {
      return try JSONDecoder().decode(SimulatorLockState.self, from: Data(line.utf8))
    } catch {
      throw SimulatorLockScreenError.undecodableState(output: output, reason: error.localizedDescription)
    }
  }
}
