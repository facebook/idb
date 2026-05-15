/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

// swiftlint:disable force_cast

@objc(FBSimulatorShutdownStrategy)
public final class FBSimulatorShutdownStrategy: NSObject {

  // MARK: - Public Methods

  @objc
  public class func shutdown(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    fbFutureFromAsync {
      try await shutdownAsync(simulator)
      return NSNull()
    }
  }

  @objc
  public class func shutdownAll(_ simulators: [FBSimulator]) -> FBFuture<NSNull> {
    fbFutureFromAsync {
      try await shutdownAllAsync(simulators)
      return NSNull()
    }
  }

  // MARK: - Async

  static func shutdownAsync(_ simulator: FBSimulator) async throws {
    let logger = simulator.logger
    logger?.debug().log("Starting Safe Shutdown of \(simulator.udid)")

    if simulator.state == .unknown {
      throw FBSimulatorError.describe("Failed to prepare simulator for usage as it is in an unknown state").build()
    }
    if simulator.state == .shutdown {
      logger?.debug().log("Shutdown of \(simulator.udid) succeeded as it is already shutdown")
      return
    }
    if simulator.state == .creating {
      try await transitionCreatingToShutdownAsync(simulator)
      return
    }
    try await shutdownSimulatorAsync(simulator)
  }

  static func shutdownAllAsync(_ simulators: [FBSimulator]) async throws {
    for simulator in simulators {
      try await shutdownAsync(simulator)
    }
  }

  // MARK: - Private

  private static let shutdownWhenShuttingDownErrorCode: Int = 164

  private static func shutdownSimulatorAsync(_ simulator: FBSimulator) async throws {
    let logger = simulator.logger
    let errorCode = shutdownWhenShuttingDownErrorCode

    logger?.debug().log("Shutting down Simulator \(simulator.udid)")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      simulator.device.shutdownAsync(withCompletionQueue: simulator.asyncQueue) { error in
        if let error = error as NSError?, error.code == errorCode {
          logger?.log("Got Error Code \(error.code) from shutdown, simulator is already shutdown")
          continuation.resume(returning: ())
        } else if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
    try await bridgeFBFutureVoid(FBiOSTargetResolveState(simulator, .shutdown))
  }

  private static func transitionCreatingToShutdownAsync(_ simulator: FBSimulator) async throws {
    do {
      try await bridgeFBFutureVoid(
        FBiOSTargetResolveState(simulator, .shutdown).timeout(
          FBControlCoreGlobalConfiguration.regularTimeout,
          waitingFor: "Simulator to resolve state \(FBiOSTargetStateString.shutdown)"
        ) as! FBFuture<NSNull>)
      return
    } catch {
      try await eraseSimulatorAsync(simulator)
    }
  }

  private static func eraseSimulatorAsync(_ simulator: FBSimulator) async throws {
    let logger = simulator.logger
    logger?.debug().log("Erasing Simulator \(simulator.udid)")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      simulator.device.eraseContentsAndSettingsAsync(withCompletionQueue: simulator.asyncQueue) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
    try await bridgeFBFutureVoid(
      FBiOSTargetResolveState(simulator, .shutdown).timeout(
        FBControlCoreGlobalConfiguration.regularTimeout,
        waitingFor: "Timed out waiting for Simulator to transition from Creating -> Shutdown"
      ) as! FBFuture<NSNull>)
  }
}
