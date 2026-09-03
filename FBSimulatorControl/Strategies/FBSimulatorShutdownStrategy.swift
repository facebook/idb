/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

final class FBSimulatorShutdownStrategy {

  // MARK: - Public Methods

  static func shutdown(_ simulator: FBSimulator) async throws {
    let logger = simulator.logger
    logger.debug().log("Starting Safe Shutdown of \(simulator.udid)")

    if simulator.state == .unknown {
      throw FBSimulatorStateError.unknownState(operation: "prepare for usage")
    }
    if simulator.state == .shutdown {
      logger.debug().log("Shutdown of \(simulator.udid) succeeded as it is already shutdown")
      return
    }
    if simulator.state == .creating {
      try await transitionCreatingToShutdownAsync(simulator)
      return
    }
    try await shutdownSimulatorAsync(simulator)
  }

  static func shutdownAll(_ simulators: [FBSimulator]) async throws {
    for simulator in simulators {
      try await shutdown(simulator)
    }
  }

  // MARK: - Private

  private static let shutdownWhenShuttingDownErrorCode: Int = 164

  private static func shutdownSimulatorAsync(_ simulator: FBSimulator) async throws {
    let logger = simulator.logger
    let errorCode = shutdownWhenShuttingDownErrorCode

    logger.debug().log("Shutting down Simulator \(simulator.udid)")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      simulator.device.shutdownAsync(withCompletionQueue: simulator.asyncQueue) { error in
        if let error = error as NSError?, error.code == errorCode {
          logger.log("Got Error Code \(error.code) from shutdown, simulator is already shutdown")
          continuation.resume(returning: ())
        } else if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
    try await FBiOSTargetResolveState(simulator, .shutdown)
  }

  private static func transitionCreatingToShutdownAsync(_ simulator: FBSimulator) async throws {
    do {
      try await FBiOSTargetResolveState(
        simulator,
        .shutdown,
        deadline: PollDeadline(
          timeout: FBControlCoreGlobalConfiguration.regularTimeout,
          waitingFor: "Simulator to resolve state \(FBiOSTargetStateString.shutdown)"))
      return
    } catch {
      try await eraseSimulatorAsync(simulator)
    }
  }

  private static func eraseSimulatorAsync(_ simulator: FBSimulator) async throws {
    let logger = simulator.logger
    logger.debug().log("Erasing Simulator \(simulator.udid)")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      simulator.device.eraseContentsAndSettingsAsync(withCompletionQueue: simulator.asyncQueue) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
    try await FBiOSTargetResolveState(
      simulator,
      .shutdown,
      deadline: PollDeadline(
        timeout: FBControlCoreGlobalConfiguration.regularTimeout,
        waitingFor: "Simulator to transition from Creating -> Shutdown"))
  }
}
