// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorInflationStrategy)
public final class FBSimulatorInflationStrategy: NSObject {

  // MARK: - Properties

  private weak var set: FBSimulatorSet?

  // MARK: - Initializers

  @objc(strategyForSet:)
  public class func strategy(for set: FBSimulatorSet) -> FBSimulatorInflationStrategy {
    return FBSimulatorInflationStrategy(set: set)
  }

  private init(set: FBSimulatorSet) {
    self.set = set
    super.init()
  }

  // MARK: - Public Methods

  @objc(inflateFromDevices:exitingSimulators:)
  public func inflate(fromDevices simDevices: [Any], exitingSimulators simulators: [FBSimulator]) -> [FBSimulator] {
    let existingSimulatorUDIDs = Set(simulators.map { $0.udid })
    var availableDevices: [String: SimDevice] = [:]
    for item in simDevices {
      let device = unsafeBitCast(item as AnyObject, to: SimDevice.self)
      availableDevices[device.udid.uuidString] = device
    }

    // Calculate the new Devices that are available.
    var simulatorsToInflate = Set(availableDevices.keys)
    simulatorsToInflate.subtract(existingSimulatorUDIDs)

    // Calculate the Devices that are now gone.
    var simulatorsToCull = existingSimulatorUDIDs
    simulatorsToCull.subtract(availableDevices.keys)

    // The hottest path, so return early to avoid doing any other work.
    if simulatorsToInflate.isEmpty && simulatorsToCull.isEmpty {
      return simulators
    }

    var result = simulators

    // Cull Simulators
    if !simulatorsToCull.isEmpty {
      let predicate = NSCompoundPredicate(notPredicateWithSubpredicate: FBiOSTargetPredicateForUDIDs(Array(simulatorsToCull)))
      result = (result as NSArray).filtered(using: predicate) as! [FBSimulator]
    }

    // Inflate the Simulators and join the array.
    let inflated = inflateSimulators(Array(simulatorsToInflate), availableDevices: availableDevices)
    return result + inflated
  }

  // MARK: - Private

  private func inflateSimulators(_ udids: [String], availableDevices: [String: SimDevice]) -> [FBSimulator] {
    guard let set = self.set else { return [] }
    var inflated: [FBSimulator] = []
    for udid in udids {
      if let device = availableDevices[udid] {
        let simulator = FBSimulator.fromSimDevice(device, configuration: nil, set: set)
        inflated.append(simulator)
      }
    }
    return inflated
  }
}
