/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@preconcurrency import Foundation

public struct FBSimulatorConfiguration: Equatable, Hashable, CustomStringConvertible {

  public let device: FBDeviceType
  public let os: FBOSVersion

  // Internal so same-module extensions can build a configuration without the throwing `defaultConfiguration()`.
  init(device: FBDeviceType, os: FBOSVersion) {
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
      return .failure(FBSimulatorConfigurationError.noDefaultDeviceTypeRegistered(model: model.rawValue))
    }
    do {
      guard let os = try FBSimulatorConfiguration.newestAvailableOS(forDevice: device) else {
        return .failure(FBSimulatorConfigurationError.noAvailableOSVersionsForDefault)
      }
      return .success(FBSimulatorConfiguration(device: device, os: os))
    } catch {
      return .failure(error)
    }
  }()

  // MARK: - Equatable, Hashable

  /// Identity is the device model and OS name, not the `FBDeviceType` and `FBOSVersion` objects
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
    let device = FBiOSTargetConfiguration.nameToDevice[model] ?? FBDeviceType.generic(withName: model.rawValue)
    return withDevice(device)
  }

  // MARK: - OS Versions

  public func withOSNamed(_ osName: FBOSVersionName) -> FBSimulatorConfiguration {
    let os = FBiOSTargetConfiguration.nameToOSVersion[osName] ?? FBOSVersion.generic(withName: osName.rawValue)
    return withOS(os)
  }

  func withOS(_ os: FBOSVersion) -> FBSimulatorConfiguration {
    FBSimulatorConfiguration(device: device, os: os)
  }

  private func withDevice(_ device: FBDeviceType) -> FBSimulatorConfiguration {
    let os = self.os
    if os.families.isEmpty || os.families.contains(NSNumber(value: device.family.rawValue)) {
      return FBSimulatorConfiguration(device: device, os: os)
    }
    let newOS = (try? FBSimulatorConfiguration.newestAvailableOS(forDevice: device)) ?? os
    return FBSimulatorConfiguration(device: device, os: newOS)
  }
}
