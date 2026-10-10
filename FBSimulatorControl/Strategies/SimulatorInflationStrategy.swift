/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

final class SimulatorInflationStrategy {

  private weak var set: SimulatorSet?

  static func strategy(for set: SimulatorSet) -> SimulatorInflationStrategy {
    SimulatorInflationStrategy(set: set)
  }

  private init(set: SimulatorSet) {
    self.set = set
  }

  func inflate(fromDevices simDevices: [Any], exitingSimulators simulators: [Simulator]) -> [Simulator] {
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
      result = result.filter { !simulatorsToCull.contains($0.udid) }
    }

    let inflated = inflateSimulators(Array(simulatorsToInflate), availableDevices: availableDevices)
    return result + inflated
  }

  private func inflateSimulators(_ udids: [String], availableDevices: [String: SimDevice]) -> [Simulator] {
    guard let set = self.set else { return [] }
    var inflated: [Simulator] = []
    for udid in udids {
      if let device = availableDevices[udid] {
        let simulator = Simulator.fromSimDevice(device, set: set)
        inflated.append(simulator)
      }
    }
    return inflated
  }
}
