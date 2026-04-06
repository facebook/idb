// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import Foundation

@objc(FBSimulatorCrashLogCommands)
public final class FBSimulatorCrashLogCommands: NSObject, FBCrashLogCommands {

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

  // MARK: - FBCrashLogCommands

  @objc
  public func notify(ofCrash predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    return notifier.nextCrashLog(forPredicate: predicate)
  }

  @objc
  public func crashes(_ predicate: NSPredicate, useCache: Bool) -> FBFuture<NSArray> {
    if !hasPerformedInitialIngestion {
      notifier.store.ingestAllExistingInDirectory()
      hasPerformedInitialIngestion = true
    }
    return FBFuture(result: notifier.store.ingestedCrashLogs(matchingPredicate: predicate) as NSArray)
  }

  @objc
  public func pruneCrashes(_ predicate: NSPredicate) -> FBFuture<NSArray> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator deallocated").build())
    }
    let simulatorPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      FBCrashLogInfo.predicate(forExecutablePathContains: simulator.udid),
      predicate,
    ])
    return FBFuture(result: notifier.store.pruneCrashLogs(matchingPredicate: simulatorPredicate) as NSArray)
  }

  @objc
  public func crashLogFiles() -> FBFutureContext<any FBFileContainerProtocol> {
    return
      FBControlCoreError
      .describe("crashLogFiles not supported on simulators")
      .failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }
}
