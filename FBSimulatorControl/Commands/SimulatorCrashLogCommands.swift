/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public enum FBSimulatorCrashLogError: Error, LocalizedError {
  case fileAccessUnsupported

  public var errorDescription: String? {
    switch self {
    case .fileAccessUnsupported:
      return "crashLogFiles not supported on simulators"
    }
  }
}

public final class FBSimulatorCrashLogCommands {

  private weak var simulator: FBSimulator?
  private let notifier: FBCrashLogNotifier
  private var hasPerformedInitialIngestion: Bool = false

  public class func commands(with simulator: FBSimulator) -> FBSimulatorCrashLogCommands {
    FBSimulatorCrashLogCommands(
      simulator: simulator,
      notifier: FBCrashLogNotifier.sharedInstance
    )
  }

  private init(simulator: FBSimulator, notifier: FBCrashLogNotifier) {
    self.simulator = simulator
    self.notifier = notifier
  }

  fileprivate func notifyOfCrash(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    try await notifier.nextCrashLog(forPredicate: predicate)
  }

  fileprivate func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    if !hasPerformedInitialIngestion {
      notifier.store.ingestAllExistingInDirectory()
      hasPerformedInitialIngestion = true
    }
    return notifier.store.ingestedCrashLogs(matchingPredicate: predicate)
  }

  fileprivate func pruneCrashes(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let simulatorPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      FBCrashLogInfo.predicate(forExecutablePathContains: simulator.udid),
      predicate,
    ])
    return notifier.store.pruneCrashLogs(matchingPredicate: simulatorPredicate)
  }
}

// MARK: - FBSimulator+CrashLogCommands

extension FBSimulator: CrashLogCommands {

  public func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    try await crashLog.crashes(matching: predicate, useCache: useCache)
  }

  public func notifyOfCrash(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    try await crashLog.notifyOfCrash(matching: predicate)
  }

  public func pruneCrashes(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    try await crashLog.pruneCrashes(matching: predicate)
  }

  public func withCrashLogFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw FBSimulatorCrashLogError.fileAccessUnsupported
  }
}
