/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public enum SimulatorCrashLogError: Error, LocalizedError {
  case fileAccessUnsupported

  public var errorDescription: String? {
    switch self {
    case .fileAccessUnsupported:
      return "crashLogFiles not supported on simulators"
    }
  }
}

public final class SimulatorCrashLogCommands: CrashLogCommands {

  private weak var simulator: Simulator?
  private let notifier: CrashLogNotifier
  private let store: CrashLogStore
  private var hasPerformedInitialIngestion: Bool = false

  public class func commands(with simulator: Simulator) -> SimulatorCrashLogCommands {
    let notifier = CrashLogNotifier.sharedInstance
    return SimulatorCrashLogCommands(simulator: simulator, notifier: notifier, store: notifier.store)
  }

  init(simulator: Simulator, notifier: CrashLogNotifier, store: CrashLogStore) {
    self.simulator = simulator
    self.notifier = notifier
    self.store = store
  }

  public func notifyOfCrash(matching predicate: CrashLogPredicate) async throws -> CrashLogInfo {
    try await notifier.nextCrashLog(forPredicate: predicate)
  }

  public func crashes(matching predicate: CrashLogPredicate, useCache: Bool) async throws -> [CrashLogInfo] {
    ingestAllCrashLogs(useCache: useCache)
    return store.ingestedCrashLogs(matchingPredicate: predicate)
  }

  public func prune(matching predicate: CrashLogPredicate) async throws -> [CrashLogInfo] {
    guard let simulator = self.simulator else {
      throw WeakTargetError.simulator
    }
    let simulatorPredicate = CrashLogPredicate.simulatorUDID(simulator.udid) && predicate
    ingestAllCrashLogs(useCache: false)
    let pruned = store.pruneCrashLogs(matchingPredicate: simulatorPredicate)
    for crashLog in pruned {
      try FileManager.default.removeItem(atPath: crashLog.crashPath)
    }
    return pruned
  }

  public func withFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw SimulatorCrashLogError.fileAccessUnsupported
  }

  private func ingestAllCrashLogs(useCache: Bool) {
    if hasPerformedInitialIngestion && useCache {
      return
    }
    store.ingestAllExistingInDirectory()
    hasPerformedInitialIngestion = true
  }
}
