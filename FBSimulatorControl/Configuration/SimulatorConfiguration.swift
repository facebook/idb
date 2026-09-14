/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@preconcurrency import Foundation

public struct FBSimulatorConfiguration: Equatable, Hashable, CustomStringConvertible, Sendable {

  public let device: DeviceType
  public let os: OSVersion
  public let deviceTypeIdentifier: String?
  public let runtimeIdentifier: String?
  public let runtimeBuildVersion: String?

  public init(
    device: DeviceType, os: OSVersion, deviceTypeIdentifier: String? = nil,
    runtimeIdentifier: String? = nil, runtimeBuildVersion: String? = nil
  ) {
    self.device = device
    self.os = os
    self.deviceTypeIdentifier = deviceTypeIdentifier
    self.runtimeIdentifier = runtimeIdentifier
    self.runtimeBuildVersion = runtimeBuildVersion
  }

  public static func defaultConfiguration() throws -> FBSimulatorConfiguration {
    try _defaultConfiguration.get()
  }

  // Memoized: the developer directory is resolved at most once, and the resolution error is preserved.
  private static let _defaultConfiguration: Result<FBSimulatorConfiguration, Error> = {
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

  public static func == (lhs: FBSimulatorConfiguration, rhs: FBSimulatorConfiguration) -> Bool {
    lhs.deviceIdentity == rhs.deviceIdentity && lhs.runtimeIdentity == rhs.runtimeIdentity
      && lhs.runtimeBuildVersion == rhs.runtimeBuildVersion
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(deviceIdentity)
    hasher.combine(runtimeIdentity)
    hasher.combine(runtimeBuildVersion)
  }

  private var deviceIdentity: String { deviceTypeIdentifier ?? device.model.rawValue }
  private enum RuntimeIdentity: Hashable {
    case identifier(String)
    case metadata(name: String, version: String)
  }

  private var runtimeIdentity: RuntimeIdentity {
    if let runtimeIdentifier {
      return .identifier(runtimeIdentifier)
    }
    return .metadata(name: os.name.rawValue, version: os.versionString)
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
