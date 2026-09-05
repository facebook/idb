/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

public enum FBSimulatorDeletionError: Error, LocalizedError {
  case removalTimedOut

  public var errorDescription: String? {
    switch self {
    case .removalTimedOut:
      return "Timed out waiting for Simulator to be removed from set"
    }
  }
}

final class FBSimulatorDeletionStrategy {

  // MARK: - Public Methods

  static func delete(_ simulator: FBSimulator) async throws {
    // Capture the Log Directory ahead of time as the Simulator will disappear on deletion.
    let coreSimulatorLogsDirectory = simulator.coreSimulatorLogsDirectory
    let udid = simulator.udid
    guard let set = simulator.set else {
      throw FBSimulatorSetError.simulatorHasNoSet(udid: simulator.udid)
    }
    let logger = simulator.logger

    logger.log("Killing Simulator, in preparation for deletion \(simulator)")
    try await FBSimulatorShutdownStrategy.shutdown(simulator)

    logger.log("Deleting Simulator \(simulator)")
    try await performDeletion(of: simulator.device, on: set.deviceSet, queue: simulator.asyncQueue)

    logger.log("Simulator \(udid) Deleted")

    if FileManager.default.fileExists(atPath: coreSimulatorLogsDirectory) {
      logger.log("Deleting Simulator Log Directory at \(coreSimulatorLogsDirectory)")
      do {
        try FileManager.default.removeItem(atPath: coreSimulatorLogsDirectory)
        logger.log("Deleted Simulator Log Directory at \(coreSimulatorLogsDirectory)")
      } catch {
        logger.error().log("Failed to delete Simulator Log Directory \(coreSimulatorLogsDirectory): \(error)")
      }
    }

    logger.log("Confirming \(udid) has been removed from set")
    try await confirmSimulatorUDID(udid, isRemovedFromSet: set)
    logger.log("\(udid) has been removed from set")
  }

  static func deleteAll(_ simulators: [FBSimulator]) async throws {
    for simulator in simulators {
      try await delete(simulator)
    }
  }

  // MARK: - Private

  private static func confirmSimulatorUDID(_ udid: String, isRemovedFromSet set: FBSimulatorSet) async throws {
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
        throw FBSimulatorDeletionError.removalTimedOut
      }
      try await Task.sleep(nanoseconds: pollIntervalNs)
    }
  }

  private static func performDeletion(of device: SimDevice, on deviceSet: SimDeviceSet, queue: DispatchQueue) async throws {
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
