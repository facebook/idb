/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

public enum FBSimulatorBootVerificationError: Error {
  case noBootInfo(simulatorDescription: String)
  case notTerminalStatus(bootInfoDescription: String)
}

extension FBSimulatorBootVerificationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .noBootInfo(simulatorDescription):
      return "No bootInfo for \(simulatorDescription)"
    case let .notTerminalStatus(bootInfoDescription):
      return "Not terminal status, status is \(bootInfoDescription)"
    }
  }
}

public final class FBSimulatorBootVerificationStrategy {

  private let simulator: FBSimulator
  private var lastBootInfo: SimDeviceBootInfo?
  private var lastInfoUpdateDate: Date?

  // MARK: - Constants

  private static let bootVerificationWaitInterval: TimeInterval = 0.5
  private static let bootVerificationStallInterval: TimeInterval = 1.5

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  static func verifySimulatorIsBooted(_ simulator: FBSimulator) async throws {
    try await FBiOSTargetResolveState(simulator, .booted)
    let strategy = FBSimulatorBootVerificationStrategy(simulator: simulator)
    let interval = UInt64(bootVerificationWaitInterval * Double(NSEC_PER_SEC))
    while true {
      try Task.checkCancellation()
      try await Task.sleep(nanoseconds: interval)
      do {
        try strategy.performBootVerificationCheck()
        return
      } catch {
        // continue polling
      }
    }
  }

  private func performBootVerificationCheck() throws {
    let bootInfo: SimDeviceBootInfo? = simulator.device.bootStatus()
    guard let bootInfo else {
      throw FBSimulatorBootVerificationError.noBootInfo(simulatorDescription: String(describing: simulator))
    }
    updateBootInfo(bootInfo)
    if bootInfo.isTerminalStatus == false {
      throw FBSimulatorBootVerificationError.notTerminalStatus(bootInfoDescription: String(describing: bootInfo))
    }
  }

  private func updateBootInfo(_ bootInfo: SimDeviceBootInfo) {
    let stallInterval = FBSimulatorBootVerificationStrategy.bootVerificationStallInterval
    let logger = simulator.logger

    let updateDate = lastInfoUpdateDate ?? Date()
    if lastInfoUpdateDate == nil {
      lastInfoUpdateDate = updateDate
    }
    if bootInfo.isEqual(lastBootInfo) {
      let updateInterval = Date().timeIntervalSince(updateDate)
      if updateInterval < stallInterval {
        return
      }
      logger.log("Boot Status has not changed from '\(bootInfo.progressDescription)' for \(updateInterval) seconds")
    } else {
      logger.debug().log("Boot Status Changed: \(bootInfo.progressDescription)")
      lastBootInfo = bootInfo
      lastInfoUpdateDate = Date()
    }
  }

}

extension SimDeviceBootInfoStatus {

  /// The status as it reads in a log line.
  var statusName: String {
    switch self {
    case .booting:
      return "Booting"
    case .waitingOnBackboard:
      return "WaitingOnBackboard"
    case .waitingOnDataMigration:
      return "WaitingOnDataMigration"
    case .waitingOnSystemApp:
      return "WaitingOnSystemApp"
    case .finished:
      return "Finished"
    case .dataMigrationFailed:
      return "DataMigrationFailed"
    @unknown default:
      return "Unknown(\(rawValue))"
    }
  }
}

extension SimDeviceBootInfo {

  /// The boot's progress as it reads in a log line: the status and how long it has taken, plus the
  /// migration detail when that is what it is waiting on.
  var progressDescription: String {
    let progress = "\(status.statusName) | Elapsed \(bootElapsedTime)"
    guard status == .waitingOnDataMigration else {
      return progress
    }
    return "\(progress) | Migration Phase '\(migrationPhaseDescription ?? "")' | Migration Elapsed \(migrationElapsedTime)"
  }
}
