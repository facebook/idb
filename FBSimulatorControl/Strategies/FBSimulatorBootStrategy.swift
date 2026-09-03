/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

final class FBSimulatorBootStrategy {

  // MARK: - Public Methods

  static func boot(_ simulator: FBSimulator, with configuration: FBSimulatorBootConfiguration) async throws {
    // Return early depending on Simulator state.
    if simulator.state == .booted {
      return
    }
    if simulator.state != .shutdown {
      throw FBSimulatorStateError.notShutdown(operation: "boot", state: simulator.stateString.rawValue)
    }

    // Boot via CoreSimulator.
    try await performSimulatorBootAsync(simulator, with: configuration)
    try await verifySimulatorIsBootedAsync(simulator, with: configuration)
  }

  // MARK: - Private

  private static func verifySimulatorIsBootedAsync(_ simulator: FBSimulator, with configuration: FBSimulatorBootConfiguration) async throws {
    // Return early if the option to verify boot is not set.
    if !configuration.options.contains(.verifyUsable) {
      return
    }
    // Otherwise actually perform the boot verification.
    try await FBSimulatorBootVerificationStrategy.verifySimulatorIsBootedAsync(simulator)
  }

  private static func performSimulatorBootAsync(_ simulator: FBSimulator, with configuration: FBSimulatorBootConfiguration) async throws {
    // "Persisting" means that the booted Simulator should live beyond the lifecycle of the process that calls the boot API.
    // The inverse of this is `FBSimulatorBootOptionsTieToProcessLifecycle`, which means that the Simulator should shutdown when the process that calls the boot API dies.
    let persist = !configuration.options.contains(.tieToProcessLifecycle)
    let options: [String: Any] = [
      "persist": persist,
      "env": configuration.environment,
    ]

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      simulator.device.bootAsync(options: options, completionQueue: simulator.workQueue) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }
}
