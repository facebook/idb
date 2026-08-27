/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The way crash-log file access fails on simulators, as data rather than an assembled string.
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

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private let notifier: FBCrashLogNotifier
  private var hasPerformedInitialIngestion: Bool = false

  // MARK: - Initializers

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

  // MARK: - Private

  fileprivate func notifyOfCrashAsync(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    try await notifier.nextCrashLog(forPredicate: predicate)
  }

  fileprivate func crashesAsync(matching predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    if !hasPerformedInitialIngestion {
      notifier.store.ingestAllExistingInDirectory()
      hasPerformedInitialIngestion = true
    }
    return notifier.store.ingestedCrashLogs(matchingPredicate: predicate)
  }

  fileprivate func pruneCrashesAsync(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
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
    try await crashLogCommands().crashesAsync(matching: predicate, useCache: useCache)
  }

  public func notifyOfCrash(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    try await crashLogCommands().notifyOfCrashAsync(matching: predicate)
  }

  public func pruneCrashes(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    try await crashLogCommands().pruneCrashesAsync(matching: predicate)
  }

  public func withCrashLogFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw FBSimulatorCrashLogError.fileAccessUnsupported
  }
}
