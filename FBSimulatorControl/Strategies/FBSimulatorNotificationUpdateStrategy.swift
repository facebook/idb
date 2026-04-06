/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorNotificationUpdateStrategy)
public final class FBSimulatorNotificationUpdateStrategy: NSObject, @unchecked Sendable {

  // MARK: - Properties

  private weak var set: FBSimulatorSet?
  private var notifier: FBCoreSimulatorNotifier?

  // MARK: - Initializers

  @objc(strategyWithSet:)
  public class func strategy(with set: FBSimulatorSet) -> FBSimulatorNotificationUpdateStrategy {
    let strategy = FBSimulatorNotificationUpdateStrategy(set: set)
    strategy.startNotifyingOfStateChanges()
    return strategy
  }

  private init(set: FBSimulatorSet) {
    self.set = set
    super.init()
  }

  deinit {
    notifier?.terminate()
    notifier = nil
  }

  // MARK: - Private

  private func startNotifyingOfStateChanges() {
    guard let set = self.set else { return }
    notifier = FBCoreSimulatorNotifier.notifier(for: set, queue: set.workQueue) { [weak self] (info: [String: Any]) in
      guard let device = info["device"] as? SimDevice else {
        return
      }
      guard let newStateNumber = info["new_state"] as? NSNumber else {
        return
      }
      self?.device(device, didChangeState: newStateNumber.uintValue)
    }
  }

  private func device(_ device: SimDevice, didChangeState state: UInt) {
    guard let set = self.set else { return }
    guard let simulator = set.simulator(withUDID: device.udid.uuidString) else {
      return
    }
    simulator.disconnect(withTimeout: FBControlCoreGlobalConfiguration.regularTimeout, logger: simulator.logger)
    set.delegate?.targetUpdated(simulator, in: simulator.set)
  }
}
