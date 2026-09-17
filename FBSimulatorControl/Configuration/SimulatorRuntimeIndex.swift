/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

struct SimulatorRuntimeIndex {
  struct Device: Equatable {
    let identifier: String
    let name: String
  }

  struct Runtime: Equatable {
    let identifier: String
    let name: String
    let version: String
    let build: String
    let available: Bool
    let supportedDevices: Set<String>
  }

  struct Match: Equatable {
    let device: Int
    let runtime: Int
  }

  let devices: [Device]
  let runtimes: [Runtime]

  func resolve(_ request: SimulatorCreationRequest) throws -> Match {
    let matchingDevices = devices.indices.filter {
      request.device.matches(identifier: devices[$0].identifier, name: devices[$0].name)
    }
    guard let device = matchingDevices.first else {
      throw SimulatorConfigurationError.noMatchingDeviceType(available: "\(devices)")
    }
    guard matchingDevices.count == 1 else {
      throw SimulatorConfigurationError.ambiguousDeviceType(matches: "\(matchingDevices.map { devices[$0] })")
    }
    let matchingRuntimes = runtimes.indices.filter {
      let runtime = runtimes[$0]
      return runtime.available && runtime.supportedDevices.contains(devices[device].identifier)
        && (request.runtime?.matches(identifier: runtime.identifier, name: runtime.name) ?? true)
    }
    guard let runtime = matchingRuntimes.max(by: { precedes(runtimes[$0], runtimes[$1]) }) else {
      throw SimulatorConfigurationError.noMatchingRuntime(available: "\(runtimes)")
    }
    return Match(device: device, runtime: runtime)
  }

  var availablePairs: [Match] {
    runtimes.indices.flatMap { runtime in
      devices.indices.compactMap { device in
        guard runtimes[runtime].available, runtimes[runtime].supportedDevices.contains(devices[device].identifier) else {
          return nil
        }
        return Match(device: device, runtime: runtime)
      }
    }
  }

  private func precedes(_ left: Runtime, _ right: Runtime) -> Bool {
    let leftVersion = OSVersion(name: OSVersionName(rawValue: left.name), versionString: left.version)
    let rightVersion = OSVersion(name: OSVersionName(rawValue: right.name), versionString: right.version)
    let versionOrder = leftVersion.compare(rightVersion)
    if versionOrder != .orderedSame {
      return versionOrder == .orderedAscending
    }
    let buildOrder = left.build.compare(right.build, options: .numeric)
    if buildOrder != .orderedSame {
      return buildOrder == .orderedAscending
    }
    return left.identifier < right.identifier
  }
}
