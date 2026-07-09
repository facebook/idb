/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

extension FBSimulatorConfiguration {

  // MARK: - Matching Configuration against Available Versions

  public class func newestAvailableOS(forDevice device: FBDeviceType) throws -> FBOSVersion? {
    try FBSimulatorConfiguration.supportedOSVersions(forDevice: device).last
  }

  @objc
  public func newestAvailableOS() throws -> FBSimulatorConfiguration {
    guard let os = try FBSimulatorConfiguration.newestAvailableOS(forDevice: device) else {
      throw FBSimulatorConfigurationError.noNewestAvailableOS(device: device.model.rawValue)
    }
    return withOSNamed(os.name)
  }

  public class func oldestAvailableOS(forDevice device: FBDeviceType) throws -> FBOSVersion? {
    try FBSimulatorConfiguration.supportedOSVersions(forDevice: device).first
  }

  @objc
  public func oldestAvailableOS() throws -> FBSimulatorConfiguration {
    guard let os = try FBSimulatorConfiguration.oldestAvailableOS(forDevice: device) else {
      throw FBSimulatorConfigurationError.noOldestAvailableOS(device: device.model.rawValue)
    }
    return withOSNamed(os.name)
  }

  @objc(inferSimulatorConfigurationFromDevice:error:)
  class func inferSimulatorConfiguration(fromDevice simDevice: SimDevice) throws -> FBSimulatorConfiguration {
    let osName = FBOSVersionName(rawValue: simDevice.runtime.name!)
    guard FBiOSTargetConfiguration.nameToOSVersion[osName] != nil else {
      throw FBSimulatorConfigurationError.unsupportedOSVersion(name: osName.rawValue)
    }
    let model = FBDeviceModel(rawValue: simDevice.deviceType.name!)
    guard FBiOSTargetConfiguration.nameToDevice[model] != nil else {
      throw FBSimulatorConfigurationError.unsupportedDevice(name: model.rawValue)
    }
    return try FBSimulatorConfiguration.defaultConfiguration().withOSNamed(osName).withDeviceModel(model)
  }

  @objc(inferSimulatorConfigurationFromDeviceSynthesizingMissing:)
  class func inferSimulatorConfigurationFromDeviceSynthesizingMissing(_ simDevice: SimDevice) -> FBSimulatorConfiguration {
    if let configuration = try? inferSimulatorConfiguration(fromDevice: simDevice) {
      return configuration
    }
    // Synthesize directly rather than via the throwing `defaultConfiguration()`: this path must not
    // fail (it has ObjC callers in non-throwing FBSimulator init) and it overrides both OS and device
    // anyway, so the default's own values are irrelevant.
    let osName = FBOSVersionName(rawValue: simDevice.runtime.name!)
    let model = FBDeviceModel(rawValue: simDevice.deviceType.name!)
    let os = FBiOSTargetConfiguration.nameToOSVersion[osName] ?? FBOSVersion.generic(withName: osName.rawValue)
    let device = FBiOSTargetConfiguration.nameToDevice[model] ?? FBDeviceType.generic(withName: model.rawValue)
    return FBSimulatorConfiguration(device: device, os: os).withDeviceModel(model)
  }

  @objc(checkRuntimeRequirementsReturningError:)
  public func checkRuntimeRequirements() throws {
    let runtime: SimRuntime
    do {
      runtime = try obtainRuntime()
    } catch {
      throw FBSimulatorConfigurationError.runtimeUnavailable(configuration: "\(self)", reason: error.localizedDescription)
    }
    let deviceType: SimDeviceType
    do {
      deviceType = try obtainDeviceType()
    } catch {
      throw FBSimulatorConfigurationError.deviceTypeUnavailable(configuration: "\(self)", reason: error.localizedDescription)
    }
    if !runtime.supportsDeviceType(deviceType) {
      throw FBSimulatorConfigurationError.runtimeDeviceTypeMismatch(
        deviceType: deviceType.name ?? "unknown",
        runtime: runtime.name ?? "unknown")
    }
  }

  @objc
  public class func supportedOSVersions() throws -> [FBOSVersion] {
    try osVersions(forRuntimes: supportedRuntimes())
  }

  @objc(supportedOSVersionsForDevice:error:)
  public class func supportedOSVersions(forDevice device: FBDeviceType) throws -> [FBOSVersion] {
    try osVersions(forRuntimes: supportedRuntimes(forDevice: device))
  }

  @objc(allAvailableDefaultConfigurationsWithLogger:error:)
  public class func allAvailableDefaultConfigrations(withLogger logger: (any FBControlCoreLogger)?) throws -> [FBSimulatorConfiguration] {
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

  @objc(allAvailableDefaultConfigurationsWithAbsentOSVersionsOut:absentDeviceTypesOut:error:)
  public class func allAvailableDefaultConfigrations(
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
      let runtimeName = runtime.name!
      let osName = FBOSVersionName(rawValue: runtimeName)
      if FBiOSTargetConfiguration.nameToOSVersion[osName] == nil {
        absentOSVersions.append(runtimeName)
        continue
      }

      for deviceType in deviceTypes {
        if !runtime.supportsDeviceType(deviceType) {
          continue
        }
        let deviceTypeName = deviceType.name!
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

  @objc(obtainRuntimeWithError:)
  func obtainRuntime() throws -> SimRuntime {
    let runtimes = try FBSimulatorConfiguration.supportedRuntimes()
    let matchingRuntimes = (runtimes as NSArray).filtered(using: runtimePredicate) as! [SimRuntime]
    if matchingRuntimes.isEmpty {
      throw FBSimulatorConfigurationError.noMatchingRuntime(available: "\(runtimes)")
    }
    if matchingRuntimes.count > 1 {
      throw FBSimulatorConfigurationError.ambiguousRuntime(matches: "\(matchingRuntimes)")
    }
    return matchingRuntimes[0]
  }

  @objc(obtainDeviceTypeWithError:)
  func obtainDeviceType() throws -> SimDeviceType {
    let deviceTypes = try FBSimulatorConfiguration.supportedDeviceTypes()
    let matchingDeviceTypes = (deviceTypes as NSArray).filtered(using: FBSimulatorConfiguration.deviceTypePredicate(device)) as! [SimDeviceType]
    if matchingDeviceTypes.isEmpty {
      throw FBSimulatorConfigurationError.noMatchingDeviceType(available: "\(matchingDeviceTypes)")
    }
    if matchingDeviceTypes.count > 1 {
      throw FBSimulatorConfigurationError.ambiguousDeviceType(matches: "\(matchingDeviceTypes)")
    }
    return matchingDeviceTypes[0]
  }

  // MARK: - Private

  private class func osVersions(forRuntimes runtimes: [SimRuntime]) -> [FBOSVersion] {
    runtimes.map { runtime in
      let name = FBOSVersionName(rawValue: runtime.name!)
      return FBiOSTargetConfiguration.nameToOSVersion[name] ?? FBOSVersion.generic(withName: runtime.name!)
    }
  }

  private class func supportedRuntimes() throws -> [SimRuntime] {
    try FBSimulatorServiceContext.sharedServiceContext().supportedRuntimes()
  }

  private class func supportedDeviceTypes() throws -> [SimDeviceType] {
    try FBSimulatorServiceContext.sharedServiceContext().supportedDeviceTypes()
  }

  private class func supportedRuntimes(forDevice device: FBDeviceType) throws -> [SimRuntime] {
    try supportedRuntimes()
      .filter { runtime in
        (runtime.supportedProductFamilyIDs as! [NSNumber]).contains(NSNumber(value: device.family.rawValue))
      }
      .sorted { left, right in
        let leftVersion = NSDecimalNumber(string: left.versionString)
        let rightVersion = NSDecimalNumber(string: right.versionString)
        return leftVersion.compare(rightVersion) == .orderedAscending
      }
  }

  private var runtimePredicate: NSPredicate {
    NSCompoundPredicate(andPredicateWithSubpredicates: [
      FBSimulatorConfiguration.runtimeProductFamilyPredicate(device),
      FBSimulatorConfiguration.runtimeNamePredicate(os),
      runtimeAvailabilityPredicate,
    ])
  }

  private class func runtimeProductFamilyPredicate(_ device: FBDeviceType) -> NSPredicate {
    NSPredicate { obj, _ in
      guard let runtime = obj as? SimRuntime else { return false }
      return (runtime.supportedProductFamilyIDs as! [NSNumber]).contains(NSNumber(value: device.family.rawValue))
    }
  }

  private class func runtimeNamePredicate(_ os: FBOSVersion) -> NSPredicate {
    NSPredicate { obj, _ in
      guard let runtime = obj as? SimRuntime else { return false }
      return runtime.name == os.name.rawValue
    }
  }

  private var runtimeAvailabilityPredicate: NSPredicate {
    NSPredicate { obj, _ in
      guard let runtime = obj as? SimRuntime else { return false }
      return runtime.available
    }
  }

  private class func deviceTypePredicate(_ device: FBDeviceType) -> NSPredicate {
    NSPredicate { obj, _ in
      guard let deviceType = obj as? SimDeviceType else { return false }
      return deviceType.name == device.model.rawValue
    }
  }
}
