/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

extension FBSimulatorConfiguration {

  // MARK: - Matching Configuration against Available Versions

  static func newestAvailableOS(forDevice device: DeviceType) throws -> OSVersion? {
    try FBSimulatorConfiguration.supportedOSVersions(forDevice: device).last
  }

  func newestAvailableOS() throws -> FBSimulatorConfiguration {
    guard let os = try FBSimulatorConfiguration.newestAvailableOS(forDevice: device) else {
      throw SimulatorConfigurationError.noNewestAvailableOS(device: device.model.rawValue)
    }
    return withOSNamed(os.name)
  }

  static func oldestAvailableOS(forDevice device: DeviceType) throws -> OSVersion? {
    try FBSimulatorConfiguration.supportedOSVersions(forDevice: device).first
  }

  func oldestAvailableOS() throws -> FBSimulatorConfiguration {
    guard let os = try FBSimulatorConfiguration.oldestAvailableOS(forDevice: device) else {
      throw SimulatorConfigurationError.noOldestAvailableOS(device: device.model.rawValue)
    }
    return withOSNamed(os.name)
  }

  public static func inferSimulatorConfiguration(fromDevice simDevice: SimDevice) throws -> FBSimulatorConfiguration {
    let osName = FBOSVersionName(rawValue: simDevice.runtime.name ?? "unknown")
    guard FBiOSTargetConfiguration.nameToOSVersion[osName] != nil else {
      throw SimulatorConfigurationError.unsupportedOSVersion(name: osName.rawValue)
    }
    let model = FBDeviceModel(rawValue: simDevice.deviceType.name ?? "unknown")
    guard FBiOSTargetConfiguration.nameToDevice[model] != nil else {
      throw SimulatorConfigurationError.unsupportedDevice(name: model.rawValue)
    }
    return try FBSimulatorConfiguration.defaultConfiguration().withOSNamed(osName).withDeviceModel(model)
  }

  public static func inferSimulatorConfigurationFromDeviceSynthesizingMissing(_ simDevice: SimDevice) -> FBSimulatorConfiguration {
    if let configuration = try? inferSimulatorConfiguration(fromDevice: simDevice) {
      return configuration
    }
    // Synthesize directly rather than via the throwing `defaultConfiguration()`: this path must not
    // fail (it has ObjC callers in non-throwing FBSimulator init) and it overrides both OS and device
    // anyway, so the default's own values are irrelevant.
    let osName = FBOSVersionName(rawValue: simDevice.runtime.name ?? "unknown")
    let model = FBDeviceModel(rawValue: simDevice.deviceType.name ?? "unknown")
    let os = FBiOSTargetConfiguration.nameToOSVersion[osName] ?? OSVersion.generic(withName: osName.rawValue)
    let device = FBiOSTargetConfiguration.nameToDevice[model] ?? DeviceType.generic(withName: model.rawValue)
    return FBSimulatorConfiguration(device: device, os: os).withDeviceModel(model)
  }

  func checkRuntimeRequirements() throws {
    let runtime: SimRuntime
    do {
      runtime = try obtainRuntime()
    } catch {
      throw SimulatorConfigurationError.runtimeUnavailable(configuration: "\(self)", reason: error.localizedDescription)
    }
    let deviceType: SimDeviceType
    do {
      deviceType = try obtainDeviceType()
    } catch {
      throw SimulatorConfigurationError.deviceTypeUnavailable(configuration: "\(self)", reason: error.localizedDescription)
    }
    if !runtime.supportsDeviceType(deviceType) {
      throw SimulatorConfigurationError.runtimeDeviceTypeMismatch(
        deviceType: deviceType.name ?? "unknown",
        runtime: runtime.name ?? "unknown")
    }
  }

  public static func supportedOSVersions() throws -> [OSVersion] {
    try osVersions(forRuntimes: supportedRuntimes())
  }

  public static func supportedOSVersions(forDevice device: DeviceType) throws -> [OSVersion] {
    try osVersions(forRuntimes: supportedRuntimes(forDevice: device))
  }

  public static func allAvailableDefaultConfigrations(withLogger logger: (any FBControlCoreLogger)?) throws -> [FBSimulatorConfiguration] {
    var absentOSVersions: NSArray?
    var absentDeviceTypes: NSArray?
    let configurations = try allAvailableDefaultConfigrations(withAbsentOSVersionsOut: &absentOSVersions, absentDeviceTypesOut: &absentDeviceTypes)
    if let absentOSVersions = absentOSVersions as? [String] {
      for osVersion in absentOSVersions {
        logger?.error().log("OS Version configuration for '\(osVersion)' is missing")
      }
    }
    if let absentDeviceTypes = absentDeviceTypes as? [String] {
      for deviceType in absentDeviceTypes {
        logger?.error().log("Device Type configuration for '\(deviceType)' is missing")
      }
    }
    return configurations
  }

  public static func allAvailableDefaultConfigrations(
    withAbsentOSVersionsOut absentOSVersionsOut: AutoreleasingUnsafeMutablePointer<NSArray?>?,
    absentDeviceTypesOut: AutoreleasingUnsafeMutablePointer<NSArray?>?
  ) throws -> [FBSimulatorConfiguration] {
    var configurations: [FBSimulatorConfiguration] = []
    var absentOSVersions: [String] = []
    var absentDeviceTypes: [String] = []
    let deviceTypes = try supportedDeviceTypes()

    for runtime in try supportedRuntimes() {
      if !runtime.available {
        continue
      }
      let runtimeName = runtime.name ?? "unknown"
      let osName = FBOSVersionName(rawValue: runtimeName)
      if FBiOSTargetConfiguration.nameToOSVersion[osName] == nil {
        absentOSVersions.append(runtimeName)
        continue
      }

      for deviceType in deviceTypes {
        if !runtime.supportsDeviceType(deviceType) {
          continue
        }
        let deviceTypeName = deviceType.name ?? "unknown"
        let model = FBDeviceModel(rawValue: deviceTypeName)
        if FBiOSTargetConfiguration.nameToDevice[model] == nil {
          absentDeviceTypes.append(deviceTypeName)
          continue
        }

        let configuration = try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(model).withOSNamed(osName)
        configurations.append(configuration)
      }
    }

    absentOSVersionsOut?.pointee = absentOSVersions as NSArray
    absentDeviceTypesOut?.pointee = absentDeviceTypes as NSArray
    return configurations
  }

  // MARK: - Obtaining CoreSimulator Classes

  func obtainRuntime() throws -> SimRuntime {
    try FBSimulatorConfiguration.resolveRuntime(for: self, from: FBSimulatorConfiguration.supportedRuntimes())
  }

  /// Pure matching over the supplied runtimes, separated from the CoreSimulator service
  /// context so the resolution rules are directly testable.
  static func resolveRuntime(for configuration: FBSimulatorConfiguration, from runtimes: [SimRuntime]) throws -> SimRuntime {
    let matchingRuntimes = runtimes.filter { runtime in
      runtime.available
        && runtime.name == configuration.os.name.rawValue
        && FBSimulatorConfiguration.runtime(runtime, supportsFamilyOf: configuration.device)
    }
    // Multiple builds of one runtime version can be installed side by side (a normal
    // beta-cycle state); a version tie resolves to the newest build rather than failing.
    // `max` is nil only for an empty collection, so the guard doubles as the no-match check.
    guard
      let newest = matchingRuntimes.max(by: { left, right in
        (left.buildVersionString ?? "").compare(right.buildVersionString ?? "", options: .numeric) == .orderedAscending
      })
    else {
      throw SimulatorConfigurationError.noMatchingRuntime(available: "\(runtimes)")
    }
    return newest
  }

  func obtainDeviceType() throws -> SimDeviceType {
    let deviceTypes = try FBSimulatorConfiguration.supportedDeviceTypes()
    let matchingDeviceTypes = deviceTypes.filter { $0.name == device.model.rawValue }
    if matchingDeviceTypes.isEmpty {
      throw SimulatorConfigurationError.noMatchingDeviceType(available: "\(matchingDeviceTypes)")
    }
    if matchingDeviceTypes.count > 1 {
      throw SimulatorConfigurationError.ambiguousDeviceType(matches: "\(matchingDeviceTypes)")
    }
    return matchingDeviceTypes[0]
  }

  // MARK: - Private

  private static func osVersions(forRuntimes runtimes: [SimRuntime]) -> [OSVersion] {
    runtimes.map { runtime in
      guard let name = FBOSVersionName(rawValue: runtime.name) else {
        return OSVersion.generic(withName: "unknown")
      }
      return FBiOSTargetConfiguration.nameToOSVersion[name] ?? OSVersion.generic(withName: name.rawValue)
    }
  }

  private static func supportedRuntimes() throws -> [SimRuntime] {
    try SimulatorServiceContext.sharedServiceContext().supportedRuntimes()
  }

  private static func supportedDeviceTypes() throws -> [SimDeviceType] {
    try SimulatorServiceContext.sharedServiceContext().supportedDeviceTypes()
  }

  private static func supportedRuntimes(forDevice device: DeviceType) throws -> [SimRuntime] {
    try supportedRuntimes()
      .filter { runtime($0, supportsFamilyOf: device) }
      .sorted { left, right in
        let leftVersion = NSDecimalNumber(string: left.versionString)
        let rightVersion = NSDecimalNumber(string: right.versionString)
        return leftVersion.compare(rightVersion) == .orderedAscending
      }
  }

  private static func runtime(_ runtime: SimRuntime, supportsFamilyOf device: DeviceType) -> Bool {
    guard let familyIDs = runtime.supportedProductFamilyIDs as? [NSNumber] else {
      return false
    }
    return familyIDs.contains(NSNumber(value: device.family.rawValue))
  }
}

extension FBOSVersionName {
  /// CoreSimulator's un-annotated headers surface `SimRuntime.name` as optional; a runtime
  /// with no name has no version name, rather than a version name made from a placeholder.
  fileprivate init?(rawValue: String?) {
    guard let rawValue else {
      return nil
    }
    self.init(rawValue: rawValue)
  }
}
