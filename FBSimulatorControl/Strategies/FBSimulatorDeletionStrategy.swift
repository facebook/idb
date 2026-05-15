/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

@objc(FBSimulatorDeletionStrategy)
public final class FBSimulatorDeletionStrategy: NSObject {

  // MARK: - Public Methods

  @objc
  public class func delete(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    fbFutureFromAsync {
      try await deleteAsync(simulator)
      return NSNull()
    }
  }

  @objc
  public class func deleteAll(_ simulators: [FBSimulator]) -> FBFuture<NSNull> {
    fbFutureFromAsync {
      try await deleteAllAsync(simulators)
      return NSNull()
    }
  }

  // MARK: - Async

  static func deleteAsync(_ simulator: FBSimulator) async throws {
    // Capture the Log Directory ahead of time as the Simulator will disappear on deletion.
    let coreSimulatorLogsDirectory = simulator.coreSimulatorLogsDirectory
    let udid = simulator.udid
    let set = simulator.set
    let logger = simulator.logger

    // Kill the Simulator before deleting it.
    logger?.log("Killing Simulator, in preparation for deletion \(simulator)")
    try await FBSimulatorShutdownStrategy.shutdownAsync(simulator)

    // Then follow through with the actual deletion of the Simulator, which will remove it from the set.
    logger?.log("Deleting Simulator \(simulator)")
    try await performDeletionAsync(of: simulator.device, on: simulator.set.deviceSet, queue: simulator.asyncQueue)

    logger?.log("Simulator \(udid) Deleted")

    // The Logfiles now need disposing of.
    if FileManager.default.fileExists(atPath: coreSimulatorLogsDirectory) {
      logger?.log("Deleting Simulator Log Directory at \(coreSimulatorLogsDirectory)")
      do {
        try FileManager.default.removeItem(atPath: coreSimulatorLogsDirectory)
        logger?.log("Deleted Simulator Log Directory at \(coreSimulatorLogsDirectory)")
      } catch {
        logger?.error().log("Failed to delete Simulator Log Directory \(coreSimulatorLogsDirectory): \(error)")
      }
    }

    logger?.log("Confirming \(udid) has been removed from set")
    try await confirmSimulatorUDIDAsync(udid, isRemovedFromSet: set)
    logger?.log("\(udid) has been removed from set")
  }

  static func deleteAllAsync(_ simulators: [FBSimulator]) async throws {
    for simulator in simulators {
      try await deleteAsync(simulator)
    }
  }

  // MARK: - Private

  private static func confirmSimulatorUDIDAsync(_ udid: String, isRemovedFromSet set: FBSimulatorSet) async throws {
    // Deleting the device from the set can still leave it around for a few seconds.
    let timeout = FBControlCoreGlobalConfiguration.regularTimeout
    let deadline = Date().addingTimeInterval(timeout)
    let pollIntervalNs = UInt64(0.1 * Double(NSEC_PER_SEC))
    while true {
      try Task.checkCancellation()
      let simulatorsInSet = Set(set.allSimulators.map { $0.udid })
      if !simulatorsInSet.contains(udid) {
        return
      }
      if Date() >= deadline {
        throw FBSimulatorError.describe("Timed out waiting for Simulator to be removed from set").build()
      }
      try await Task.sleep(nanoseconds: pollIntervalNs)
    }
  }

  private static func performDeletionAsync(of device: SimDevice, on deviceSet: SimDeviceSet, queue: DispatchQueue) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      deviceSet.deleteDeviceAsync(device, completionQueue: queue) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }
}
