/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

private let bootVerificationPollInterval: TimeInterval = 0.5
private let bootVerificationStallInterval: TimeInterval = 1.5

/// Waits until `simulator` has finished booting. `.booted` is not that signal — it is reported the
/// moment the boot is underway — so this waits for the state and then for the boot status to reach
/// a terminal value.
///
/// Public: consumers outside this module wait on simulators they booted for the state only.
public func verifySimulatorIsBooted(_ simulator: FBSimulator) async throws {
  try await FBiOSTargetResolveState(simulator, .booted)

  var lastBootInfo: SimDeviceBootInfo?
  var lastChange = Date()

  while true {
    try Task.checkCancellation()
    if let bootInfo = simulator.device.bootStatus() {
      if bootInfo.isEqual(lastBootInfo) {
        let stalledFor = Date().timeIntervalSince(lastChange)
        if stalledFor >= bootVerificationStallInterval {
          simulator.logger.log("Boot Status has not changed from '\(bootInfo.progressDescription)' for \(stalledFor) seconds")
        }
      } else {
        simulator.logger.debug().log("Boot Status Changed: \(bootInfo.progressDescription)")
        lastBootInfo = bootInfo
        lastChange = Date()
      }
      if bootInfo.isTerminalStatus {
        return
      }
    }
    try await Task.sleep(nanoseconds: UInt64(bootVerificationPollInterval * Double(NSEC_PER_SEC)))
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
