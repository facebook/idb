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
    let metadata = resolvedMetadata(from: simDevice)
    guard let runtimeName = metadata.runtimeName else {
      throw FBSimulatorConfigurationError.missingRuntimeMetadata(identifier: simDevice.runtimeIdentifier)
    }
    let osName = FBOSVersionName(rawValue: runtimeName)
    guard FBiOSTargetConfiguration.nameToOSVersion[osName] != nil else {
      throw FBSimulatorConfigurationError.unsupportedOSVersion(name: osName.rawValue)
    }
    guard let deviceModelName = metadata.deviceModelName else {
      throw FBSimulatorConfigurationError.missingDeviceTypeMetadata(identifier: simDevice.deviceTypeIdentifier)
    }
    let model = FBDeviceModel(rawValue: deviceModelName)
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
    let metadata = resolvedMetadata(from: simDevice)
    return synthesizedConfiguration(
      runtimeName: metadata.runtimeName,
      deviceModelName: metadata.deviceModelName,
      fallback: try? defaultConfiguration())
  }

  static func synthesizedConfiguration(
    runtimeName: String?,
    deviceModelName: String?,
    fallback: FBSimulatorConfiguration?
  ) -> FBSimulatorConfiguration {
    let osName = runtimeName.map(FBOSVersionName.init(rawValue:))
      ?? fallback?.os.name
      ?? FBOSVersionName(rawValue: "Unknown Runtime")
    let model = deviceModelName.map(FBDeviceModel.init(rawValue:))
      ?? fallback?.device.model
      ?? FBDeviceModel(rawValue: "Unknown Device")
    let os = FBiOSTargetConfiguration.nameToOSVersion[osName] ?? FBOSVersion.generic(withName: osName.rawValue)
    let device = FBiOSTargetConfiguration.nameToDevice[model] ?? FBDeviceType.generic(withName: model.rawValue)
    return FBSimulatorConfiguration(device: device, os: os)
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
    let matchingRuntimes = runtimes.filter { runtimePredicate.evaluate(with: $0) }
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
    let predicate = FBSimulatorConfiguration.deviceTypePredicate(device)
    let matchingDeviceTypes = deviceTypes.filter { predicate.evaluate(with: $0) }
    if matchingDeviceTypes.isEmpty {
      throw FBSimulatorConfigurationError.noMatchingDeviceType(available: "\(deviceTypes)")
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

  private struct ResolvedMetadata {
    let runtimeName: String?
    let deviceModelName: String?
  }

  private class func resolvedMetadata(from simDevice: SimDevice) -> ResolvedMetadata {
    let runtimeIdentifier = nonEmpty(simDevice.runtimeIdentifier)
    // Prefer the real CoreSimulator runtime name (safe KVC lookup that tolerates
    // cryptex runtimes with missing metadata), then a supportedRuntimes() identifier
    // lookup. Synthesizing a name from the identifier is a last resort only: it can
    // diverge from the installed runtime's actual name (e.g. "iOS 10.3" vs
    // "iOS 10.3.1", or the "xrOS" identifier prefix vs the "visionOS" display name),
    // which would break exact-name runtime matching.
    let runtimeName = resolvedMetadataName(
      directName: metadataName(forKey: "runtime", from: simDevice),
      identifier: runtimeIdentifier
    ) {
      try supportedRuntimes().map { (identifier: $0.identifier, name: $0.name) }
    }
      ?? runtimeName(fromIdentifier: runtimeIdentifier)
    let deviceModelName = resolvedMetadataName(
      directName: metadataName(forKey: "deviceType", from: simDevice),
      identifier: simDevice.deviceTypeIdentifier
    ) {
      try supportedDeviceTypes().map { (identifier: $0.identifier, name: $0.name) }
    }
    return ResolvedMetadata(runtimeName: runtimeName, deviceModelName: deviceModelName)
  }

  static func resolvedMetadataName(
    directName: String?,
    identifier: String?,
    candidates: () throws -> [(identifier: String?, name: String?)]
  ) -> String? {
    if let directName = nonEmpty(directName) {
      return directName
    }
    guard let identifier = nonEmpty(identifier),
      let candidates = try? candidates()
    else {
      return nil
    }
    return candidates.first { nonEmpty($0.identifier) == identifier }
      .flatMap { nonEmpty($0.name) }
  }

  static func runtimeName(fromIdentifier identifier: String?) -> String? {
    let prefix = "com.apple.CoreSimulator.SimRuntime."
    guard let identifier = nonEmpty(identifier), identifier.hasPrefix(prefix) else {
      return nil
    }
    let components = identifier.dropFirst(prefix.count).split(separator: "-")
    guard components.count >= 2 else {
      return nil
    }
    let platform = components[0]
    let versionComponents = components.dropFirst()
    guard versionComponents.allSatisfy({ Int($0) != nil }) else {
      return nil
    }
    return "\(platform) \(versionComponents.joined(separator: "."))"
  }

  private static func metadataName(forKey key: String, from simDevice: SimDevice) -> String? {
    guard let metadata = simDevice.value(forKey: key) as? NSObject else {
      return nil
    }
    return nonEmpty(metadata.value(forKey: "name") as? String)
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
      return nil
    }
    return value
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
