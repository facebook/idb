/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

final class FBSimulatorInflationStrategy {

  // MARK: - Properties

  private weak var set: FBSimulatorSet?

  // MARK: - Initializers

  class func strategy(for set: FBSimulatorSet) -> FBSimulatorInflationStrategy {
    FBSimulatorInflationStrategy(set: set)
  }

  private init(set: FBSimulatorSet) {
    self.set = set
  }

  // MARK: - Public Methods

  func inflate(fromDevices simDevices: [Any], exitingSimulators simulators: [FBSimulator]) -> [FBSimulator] {
    let existingSimulatorUDIDs = Set(simulators.map { $0.udid })
    var availableDevices: [String: SimDevice] = [:]
    for item in simDevices {
      let device = unsafeBitCast(item as AnyObject, to: SimDevice.self)
      availableDevices[device.udid.uuidString] = device
    }

    var simulatorsToInflate = Set(availableDevices.keys)
    simulatorsToInflate.subtract(existingSimulatorUDIDs)

    var simulatorsToCull = existingSimulatorUDIDs
    simulatorsToCull.subtract(availableDevices.keys)

    // The hottest path, so return early to avoid doing any other work.
    if simulatorsToInflate.isEmpty && simulatorsToCull.isEmpty {
      return simulators
    }

    var result = simulators

    if !simulatorsToCull.isEmpty {
      let culled = FBiOSTargetPredicateForUDIDs(Array(simulatorsToCull))
      result = result.filter { !culled.evaluate(with: $0) }
    }

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
