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
    if simulator.state == .booted {
      return
    }
    if simulator.state != .shutdown {
      throw FBSimulatorStateError.notShutdown(operation: "boot", state: simulator.stateString.rawValue)
    }

    try await performSimulatorBoot(simulator, with: configuration)
    try await verifySimulatorIsBooted(simulator, with: configuration)
  }

  // MARK: - Private

  private static func verifySimulatorIsBooted(_ simulator: FBSimulator, with configuration: FBSimulatorBootConfiguration) async throws {
    if !configuration.options.contains(.verifyUsable) {
      return
    }
    try await FBSimulatorBootVerificationStrategy.verifySimulatorIsBootedAsync(simulator)
  }

  private static func performSimulatorBoot(_ simulator: FBSimulator, with configuration: FBSimulatorBootConfiguration) async throws {
    // "persist": the booted Simulator outlives the calling process; `.tieToProcessLifecycle` is its inverse.
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
