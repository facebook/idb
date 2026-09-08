/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Foundation

/// The failures of running a service inside the guest with `SimulatorFrameworkBridge`.
public enum FBSimulatorFrameworkBridgeError: Error, LocalizedError {

  /// The bridge binary is not present in the companion's Resources directory.
  case binaryMissing

  /// The bridge ran and reported a failure.
  case serviceFailed(service: String, action: String, exitCode: Int32, stderr: String)

  public var errorDescription: String? {
    switch self {
    case .binaryMissing:
      return "SimulatorFrameworkBridge binary not found in the companion Resources directory"
    case let .serviceFailed(service, action, exitCode, stderr):
      return "SimulatorFrameworkBridge \(service) \(action) failed with exit code \(exitCode): \(stderr)"
    }
  }
}

// MARK: - SimulatorFrameworkBridge

extension FBSimulator {

  /// Runs one of `SimulatorFrameworkBridge`'s services inside the guest, returning its stdout.
  ///
  /// The bridge is a guest binary spawned into the booted simulator, so it reaches frameworks and
  /// daemons that exist only there. `ServiceDispatch.m` holds the set of services and their actions.
  @discardableResult
  func runSimulatorFrameworkBridge(
    withService service: String,
    action: String,
    arguments: [String] = []
  ) async throws -> String {
    guard let helperPath = BundledResources.path(forItem: "SimulatorFrameworkBridge") else {
      throw FBSimulatorFrameworkBridgeError.binaryMissing
    }

    let output = try await launchProcessConsumingOutput(
      launchPath: helperPath,
      arguments: [service, action] + arguments)
    guard output.exitCode == 0 else {
      let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
      throw FBSimulatorFrameworkBridgeError.serviceFailed(
        service: service,
        action: action,
        exitCode: output.exitCode,
        stderr: stderr)
    }
    logger.log("SimulatorFrameworkBridge \(service) \(action) completed successfully")
    return String(data: output.stdout, encoding: .utf8) ?? ""
  }
}
