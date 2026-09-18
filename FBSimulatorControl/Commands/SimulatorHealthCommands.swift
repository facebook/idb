/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// Manages an application's HealthKit authorization for individual sample types.
public struct SimulatorHealthCommands {

  private let simulator: Simulator

  // MARK: - Initializers

  public static func commands(with simulator: Simulator) -> SimulatorHealthCommands {
    SimulatorHealthCommands(simulator: simulator)
  }

  internal init(simulator: Simulator) {
    self.simulator = simulator
  }

  // MARK: - Authorization

  public func set(_ approved: Bool, forBundleID bundleID: String, typeIdentifiers: [String]) async throws {
    let action = approved ? "approve" : "revoke"
    let args = [bundleID] + typeIdentifiers
    try await simulator.runSimulatorFrameworkBridge(withService: "health", action: action, arguments: args)
  }

  public func clear(forBundleID bundleID: String) async throws {
    try await simulator.runSimulatorFrameworkBridge(withService: "health", action: "clear", arguments: [bundleID])
  }

  public func list(forBundleID bundleID: String) async throws -> String {
    try await simulator.runSimulatorFrameworkBridge(withService: "health", action: "list", arguments: [bundleID])
  }
}
