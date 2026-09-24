/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import SimulatorFrameworkBridgeProtocol

/// The failures of running a service inside the guest with `SimulatorFrameworkBridge`.
public enum SimulatorFrameworkBridgeError: Error, LocalizedError {

  /// The bridge binary is not present in the companion's Resources directory.
  case binaryMissing

  case requestFailed(command: BridgeCommand, exitCode: Int32, output: String)

  /// The bridge ran and reported a failure.
  case serviceFailed(service: String, action: String, exitCode: Int32, stderr: String)

  static func failureDetails(stderr: Data, stdout: Data) -> String {
    let details = [stderr, stdout]
      .compactMap { String(data: $0, encoding: .utf8) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    return details.isEmpty ? "no output" : details
  }

  public var errorDescription: String? {
    switch self {
    case .binaryMissing:
      return "SimulatorFrameworkBridge binary not found in the companion Resources directory"
    case let .requestFailed(command, exitCode, output):
      return "SimulatorFrameworkBridge \(command) failed with exit code \(exitCode): \(output.isEmpty ? "no output" : output)"
    case let .serviceFailed(service, action, exitCode, stderr):
      return "SimulatorFrameworkBridge \(service) \(action) failed with exit code \(exitCode): \(stderr)"
    }
  }
}

// MARK: - SimulatorFrameworkBridge

extension Simulator {

  /// Runs a positional `SimulatorFrameworkBridge` command for services that `BridgeCommand` does not model yet.
  @discardableResult
  func runSimulatorFrameworkBridge(
    withService service: String,
    action: String,
    arguments: [String] = []
  ) async throws -> String {
    guard let bundledGuestPath = frameworkBridgePath else {
      throw SimulatorFrameworkBridgeError.binaryMissing
    }
    let output = try await runtimeTools.launchConsumingOutput(
      launchPath: bundledGuestPath,
      arguments: [service, action] + arguments)
    guard output.exitCode == 0 else {
      let details = SimulatorFrameworkBridgeError.failureDetails(
        stderr: output.stderr,
        stdout: output.stdout)
      throw SimulatorFrameworkBridgeError.serviceFailed(
        service: service,
        action: action,
        exitCode: output.exitCode,
        stderr: details)
    }
    logger.log("SimulatorFrameworkBridge \(service) \(action) completed successfully")
    return String(data: output.stdout, encoding: .utf8) ?? ""
  }
}
