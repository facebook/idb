/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorBootVerificationStrategy)
public final class FBSimulatorBootVerificationStrategy: NSObject {

  // MARK: - Properties

  private let simulator: FBSimulator
  private var lastBootInfo: SimDeviceBootInfo?
  private var lastInfoUpdateDate: Date?

  // MARK: - Constants

  private static let bootVerificationWaitInterval: TimeInterval = 0.5 // 500ms
  private static let bootVerificationStallInterval: TimeInterval = 1.5 // 1.5s

  // MARK: - Initializers

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Public Methods

  @objc
  public class func verifySimulatorIsBooted(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    fbFutureFromAsync {
      try await verifySimulatorIsBootedAsync(simulator)
      return NSNull()
    }
  }

  // MARK: - Async

  static func verifySimulatorIsBootedAsync(_ simulator: FBSimulator) async throws {
    try await bridgeFBFutureVoid(FBiOSTargetResolveState(simulator, .booted))
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

  // MARK: - Private

  private func performBootVerificationCheck() throws {
    let bootInfo: SimDeviceBootInfo? = simulator.device.bootStatus()
    guard let bootInfo else {
      throw FBSimulatorError.describe("No bootInfo for \(simulator)").build()
    }
    updateBootInfo(bootInfo)
    if bootInfo.isTerminalStatus == false {
      throw FBSimulatorError.describe("Not terminal status, status is \(String(describing: bootInfo))").build()
    }
  }

  private func updateBootInfo(_ bootInfo: SimDeviceBootInfo) {
    let stallInterval = FBSimulatorBootVerificationStrategy.bootVerificationStallInterval
    let logger = simulator.logger

    if lastInfoUpdateDate == nil {
      lastInfoUpdateDate = Date()
    }
    if bootInfo.isEqual(lastBootInfo) {
      let updateInterval = Date().timeIntervalSince(lastInfoUpdateDate!)
      if updateInterval < stallInterval {
        return
      }
      logger?.log("Boot Status has not changed from '\(FBSimulatorBootVerificationStrategy.describeBootInfo(bootInfo))' for \(updateInterval) seconds")
    } else {
      logger?.debug().log("Boot Status Changed: \(FBSimulatorBootVerificationStrategy.describeBootInfo(bootInfo))")
      lastBootInfo = bootInfo
      lastInfoUpdateDate = Date()
    }
  }

  private class func describeBootInfo(_ bootInfo: SimDeviceBootInfo) -> String {
    let regular = regularBootInfo(bootInfo)
    guard let migration = dataMigrationString(bootInfo) else {
      return regular
    }
    return "\(regular) | \(migration)"
  }

  private class func regularBootInfo(_ bootInfo: SimDeviceBootInfo) -> String {
    return "\(bootStatusString(bootInfo.status)) | Elapsed \(bootInfo.bootElapsedTime)"
  }

  private class func bootStatusString(_ status: SimDeviceBootInfoStatus) -> String {
    switch status {
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
    default:
      return "Unknown"
    }
  }

  private class func dataMigrationString(_ bootInfo: SimDeviceBootInfo) -> String? {
    if bootInfo.status != .waitingOnDataMigration {
      return nil
    }
    return "Migration Phase '\(bootInfo.migrationPhaseDescription ?? "")' | Migration Elapsed \(bootInfo.migrationElapsedTime)"
  }
}
