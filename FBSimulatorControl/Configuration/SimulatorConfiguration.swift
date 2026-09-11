/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@preconcurrency import Foundation

public struct FBSimulatorConfiguration: Equatable, Hashable, CustomStringConvertible {

  public let device: DeviceType
  public let os: OSVersion

  // Internal so same-module extensions can build a configuration without the throwing `defaultConfiguration()`.
  init(device: DeviceType, os: OSVersion) {
    self.device = device
    self.os = os
  }

  public static func defaultConfiguration() throws -> FBSimulatorConfiguration {
    try _defaultConfiguration.get()
  }

  // Memoized: the developer directory is resolved at most once, and the resolution error is preserved.
  private nonisolated(unsafe) static let _defaultConfiguration: Result<FBSimulatorConfiguration, Error> = {
    do {
      try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)
    } catch {
      return .failure(error)
    }
    let model = FBDeviceModel(rawValue: "iPhone 6")
    guard let device = FBiOSTargetConfiguration.nameToDevice[model] else {
      return .failure(SimulatorConfigurationError.noDefaultDeviceTypeRegistered(model: model.rawValue))
    }
    do {
      guard let os = try FBSimulatorConfiguration.newestAvailableOS(forDevice: device) else {
        return .failure(SimulatorConfigurationError.noAvailableOSVersionsForDefault)
      }
      return .success(FBSimulatorConfiguration(device: device, os: os))
    } catch {
      return .failure(error)
    }
  }()

  // MARK: - Equatable, Hashable

  /// Identity is the device model and OS name, not the `DeviceType` and `OSVersion` objects
  /// carrying them — two configurations naming the same model and OS are the same configuration.
  public static func == (lhs: FBSimulatorConfiguration, rhs: FBSimulatorConfiguration) -> Bool {
    lhs.device.model == rhs.device.model && lhs.os.name == rhs.os.name
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(device.model.rawValue)
    hasher.combine(os.name.rawValue)
  }

  public var description: String {
    "Device '\(device.model.rawValue)' | OS Version '\(os.name.rawValue)'"
  }

  // MARK: - Models

  public func withDeviceModel(_ model: FBDeviceModel) -> FBSimulatorConfiguration {
    let device = FBiOSTargetConfiguration.nameToDevice[model] ?? DeviceType.generic(withName: model.rawValue)
    return withDevice(device)
  }

  // MARK: - OS Versions

  public func withOSNamed(_ osName: FBOSVersionName) -> FBSimulatorConfiguration {
    let os = FBiOSTargetConfiguration.nameToOSVersion[osName] ?? OSVersion.generic(withName: osName.rawValue)
    return withOS(os)
  }

  func withOS(_ os: OSVersion) -> FBSimulatorConfiguration {
    FBSimulatorConfiguration(device: device, os: os)
  }

  private func withDevice(_ device: DeviceType) -> FBSimulatorConfiguration {
    let os = self.os
    if os.families.isEmpty || os.families.contains(NSNumber(value: device.family.rawValue)) {
      return FBSimulatorConfiguration(device: device, os: os)
    }
    let newOS = (try? FBSimulatorConfiguration.newestAvailableOS(forDevice: device)) ?? os
    return FBSimulatorConfiguration(device: device, os: newOS)
  }
}
