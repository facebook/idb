/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// swiftlint:disable force_cast

@objc(FBSimulatorCrashLogCommands)
public final class FBSimulatorCrashLogCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private let notifier: FBCrashLogNotifier
  private var hasPerformedInitialIngestion: Bool = false

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorCrashLogCommands {
    return FBSimulatorCrashLogCommands(
      simulator: target as! FBSimulator,
      notifier: FBCrashLogNotifier.sharedInstance
    )
  }

  private init(simulator: FBSimulator, notifier: FBCrashLogNotifier) {
    self.simulator = simulator
    self.notifier = notifier
    super.init()
  }

  // MARK: - FBCrashLogCommands (legacy FBFuture entry point)

  @objc(notifyOfCrash:)
  public func notifyOfCrash(_ predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    return notifier.nextCrashLog(forPredicate: predicate)
  }

  // MARK: - Private

  fileprivate func notifyOfCrashAsync(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    try await bridgeFBFuture(notifier.nextCrashLog(forPredicate: predicate))
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
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let simulatorPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      FBCrashLogInfo.predicate(forExecutablePathContains: simulator.udid),
      predicate,
    ])
    return notifier.store.pruneCrashLogs(matchingPredicate: simulatorPredicate)
  }
}

// MARK: - FBSimulator+AsyncCrashLogCommands

extension FBSimulator: AsyncCrashLogCommands {

  public func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    try await crashLogCommands().crashesAsync(matching: predicate, useCache: useCache)
  }

  public func notifyOfCrash(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    try await crashLogCommands().notifyOfCrashAsync(matching: predicate)
  }

  public func pruneCrashes(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    try await crashLogCommands().pruneCrashesAsync(matching: predicate)
  }

  public func withCrashLogFiles<R>(body: (any FBFileContainerProtocol) async throws -> R) async throws -> R {
    throw FBControlCoreError.describe("crashLogFiles not supported on simulators").build()
  }
}

// MARK: - FBSimulator+FBCrashLogCommands

extension FBSimulator {

  @objc(notifyOfCrash:)
  public func notifyOfCrash(_ predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    do {
      return try crashLogCommands().notifyOfCrash(predicate)
    } catch {
      return FBFuture(error: error)
    }
  }
}
