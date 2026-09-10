/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@preconcurrency import Foundation

public enum SimulatorNetworkError: Error, LocalizedError {
  case noDnsServers

  public var errorDescription: String? {
    switch self {
    case .noDnsServers:
      return "At least one DNS server address is required"
    }
  }
}

/// Configures the HTTP proxy and DNS resolvers the simulated device uses.
public struct SimulatorNetworkCommands {

  private let simulator: FBSimulator

  // MARK: - Initializers

  public static func commands(with simulator: FBSimulator) -> SimulatorNetworkCommands {
    SimulatorNetworkCommands(simulator: simulator)
  }

  internal init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Proxy

  public func setProxy(host: String, port: UInt, type: String) async throws {
    try await simulator.runSimulatorFrameworkBridge(
      withService: "proxy",
      action: "set",
      arguments: [host, "\(port)", type.isEmpty ? "http" : type])
  }

  public func clearProxy() async throws {
    try await simulator.runSimulatorFrameworkBridge(withService: "proxy", action: "clear")
  }

  public func listProxy() async throws -> String {
    try await simulator.runSimulatorFrameworkBridge(withService: "proxy", action: "list")
  }

  // MARK: - DNS

  public func setDnsServers(_ servers: [String]) async throws {
    if servers.isEmpty {
      throw SimulatorNetworkError.noDnsServers
    }
    try await simulator.runSimulatorFrameworkBridge(withService: "dns", action: "set", arguments: servers)
  }

  public func clearDns() async throws {
    try await simulator.runSimulatorFrameworkBridge(withService: "dns", action: "clear")
  }

  public func listDns() async throws -> String {
    try await simulator.runSimulatorFrameworkBridge(withService: "dns", action: "list")
  }
}
