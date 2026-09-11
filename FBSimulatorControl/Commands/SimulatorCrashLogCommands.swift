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

  private weak var simulator: FBSimulator?
  private let notifier: CrashLogNotifier
  private var hasPerformedInitialIngestion: Bool = false

  public class func commands(with simulator: FBSimulator) -> SimulatorCrashLogCommands {
    SimulatorCrashLogCommands(
      simulator: simulator,
      notifier: CrashLogNotifier.sharedInstance
    )
  }

  private init(simulator: FBSimulator, notifier: CrashLogNotifier) {
    self.simulator = simulator
    self.notifier = notifier
  }

  public func notifyOfCrash(matching predicate: NSPredicate) async throws -> CrashLogInfo {
    try await notifier.nextCrashLog(forPredicate: predicate)
  }

  public func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [CrashLogInfo] {
    if !hasPerformedInitialIngestion {
      notifier.store.ingestAllExistingInDirectory()
      hasPerformedInitialIngestion = true
    }
    return notifier.store.ingestedCrashLogs(matchingPredicate: predicate)
  }

  public func pruneCrashes(matching predicate: NSPredicate) async throws -> [CrashLogInfo] {
    guard let simulator = self.simulator else {
      throw WeakTargetError.simulator
    }
    let simulatorPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      CrashLogInfo.predicate(forExecutablePathContains: simulator.udid),
      predicate,
    ])
    return notifier.store.pruneCrashLogs(matchingPredicate: simulatorPredicate)
  }

  public func withFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw SimulatorCrashLogError.fileAccessUnsupported
  }
}
