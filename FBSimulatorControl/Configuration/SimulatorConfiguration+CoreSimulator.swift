/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

extension SimulatorConfiguration {

  public static func inferSimulatorConfiguration(fromDevice simDevice: SimDevice) -> SimulatorConfiguration {
    configuration(deviceType: simDevice.deviceType, runtime: simDevice.runtime)
  }

  static func configuration(deviceType: SimDeviceType?, runtime: SimRuntime?) -> SimulatorConfiguration {
    let family: FBControlCoreProductFamily
    switch deviceType?.productFamilyID {
    case 1: family = .familyiPhone
    case 2: family = .familyiPad
    case 3: family = .familyAppleTV
    case 4: family = .familyAppleWatch
    case 5: family = .familyMac
    default: family = .familyUnknown
    }
    return SimulatorConfiguration(
      device: DeviceType(model: FBDeviceModel(rawValue: deviceType?.name ?? "unknown"), family: family),
      os: OSVersion(name: FBOSVersionName(rawValue: runtime?.name ?? "unknown"), versionString: runtime?.versionString ?? ""),
      deviceTypeIdentifier: deviceType?.identifier,
      runtimeIdentifier: runtime?.identifier,
      runtimeBuildVersion: runtime?.buildVersionString)
  }

  public static func availableConfigurations() throws -> [SimulatorConfiguration] {
    let snapshot = try CoreSimulatorRuntimeIndex.load()
    return snapshot.index.availablePairs.map {
      configuration(deviceType: snapshot.deviceTypes[$0.device], runtime: snapshot.runtimes[$0.runtime])
    }
  }
}
