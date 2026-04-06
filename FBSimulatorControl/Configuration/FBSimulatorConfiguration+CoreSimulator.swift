// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

extension FBSimulatorConfiguration {

  // MARK: - Matching Configuration against Available Versions

  @objc(newestAvailableOSForDevice:)
  public class func newestAvailableOS(forDevice device: FBDeviceType) -> FBOSVersion? {
    return FBSimulatorConfiguration.supportedOSVersions(forDevice: device).last
  }

  @objc
  public func newestAvailableOS() -> FBSimulatorConfiguration {
    let os = FBSimulatorConfiguration.newestAvailableOS(forDevice: device)!
    return withOSNamed(os.name)
  }

  @objc(oldestAvailableOSForDevice:)
  public class func oldestAvailableOS(forDevice device: FBDeviceType) -> FBOSVersion? {
    return FBSimulatorConfiguration.supportedOSVersions(forDevice: device).first
  }

  @objc
  public func oldestAvailableOS() -> FBSimulatorConfiguration {
    let os = FBSimulatorConfiguration.oldestAvailableOS(forDevice: device)!
    return withOSNamed(os.name)
  }

  @objc(inferSimulatorConfigurationFromDevice:error:)
  public class func inferSimulatorConfiguration(fromDevice simDevice: SimDevice) throws -> FBSimulatorConfiguration {
    let osName = FBOSVersionName(rawValue: simDevice.runtime.name!)
    guard FBiOSTargetConfiguration.nameToOSVersion[osName] != nil else {
      throw FBSimulatorError.describe("Could not obtain OS Version for \(osName.rawValue), perhaps it is unsupported by FBSimulatorControl").build()
    }
    let model = FBDeviceModel(rawValue: simDevice.deviceType.name!)
    guard FBiOSTargetConfiguration.nameToDevice[model] != nil else {
      throw FBSimulatorError.describe("Could not obtain Device for \(model.rawValue), perhaps it is unsupported by FBSimulatorControl").build()
    }
    return FBSimulatorConfiguration.defaultConfiguration.withOSNamed(osName).withDeviceModel(model)
  }

  @objc(inferSimulatorConfigurationFromDeviceSynthesizingMissing:)
  public class func inferSimulatorConfigurationFromDeviceSynthesizingMissing(_ simDevice: SimDevice) -> FBSimulatorConfiguration {
    if let configuration = try? inferSimulatorConfiguration(fromDevice: simDevice) {
      return configuration
    }
    let osName = FBOSVersionName(rawValue: simDevice.runtime.name!)
    let model = FBDeviceModel(rawValue: simDevice.deviceType.name!)
    return FBSimulatorConfiguration.defaultConfiguration.withOSNamed(osName).withDeviceModel(model)
  }

  @objc(checkRuntimeRequirementsReturningError:)
  public func checkRuntimeRequirements() throws {
    let runtime: SimRuntime
    do {
      runtime = try obtainRuntime()
    } catch {
      throw FBSimulatorError.describe("Could not obtain available SimRuntime for configuration \(self)").caused(by: error).build()
    }
    let deviceType: SimDeviceType
    do {
      deviceType = try obtainDeviceType()
    } catch {
      throw FBSimulatorError.describe("Could not obtain available SimDeviceType for configuration \(self)").caused(by: error).build()
    }
    if !runtime.supportsDeviceType(deviceType) {
      throw FBSimulatorError.describe("Device Type \(deviceType.name ?? "unknown") does not support Runtime \(runtime.name ?? "unknown")").build()
    }
  }

  @objc
  public class func supportedOSVersions() -> [FBOSVersion] {
    return osVersions(forRuntimes: supportedRuntimes())
  }

  @objc(supportedOSVersionsForDevice:)
  public class func supportedOSVersions(forDevice device: FBDeviceType) -> [FBOSVersion] {
    return osVersions(forRuntimes: supportedRuntimes(forDevice: device))
  }

  @objc(allAvailableDefaultConfigurationsWithLogger:)
  public class func allAvailableDefaultConfigrations(withLogger logger: (any FBControlCoreLogger)?) -> [FBSimulatorConfiguration] {
    var absentOSVersions: NSArray?
    var absentDeviceTypes: NSArray?
    let configurations = allAvailableDefaultConfigrations(withAbsentOSVersionsOut: &absentOSVersions, absentDeviceTypesOut: &absentDeviceTypes)
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

  @objc(allAvailableDefaultConfigurationsWithAbsentOSVersionsOut:absentDeviceTypesOut:)
  public class func allAvailableDefaultConfigrations(
    withAbsentOSVersionsOut absentOSVersionsOut: AutoreleasingUnsafeMutablePointer<NSArray?>?,
    absentDeviceTypesOut: AutoreleasingUnsafeMutablePointer<NSArray?>?
  ) -> [FBSimulatorConfiguration] {
    var configurations: [FBSimulatorConfiguration] = []
    var absentOSVersions: [String] = []
    var absentDeviceTypes: [String] = []
    let deviceTypes = supportedDeviceTypes()

    for runtime in supportedRuntimes() {
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

        let configuration = FBSimulatorConfiguration.defaultConfiguration.withDeviceModel(model).withOSNamed(osName)
        configurations.append(configuration)
      }
    }

    absentOSVersionsOut?.pointee = absentOSVersions as NSArray
    absentDeviceTypesOut?.pointee = absentDeviceTypes as NSArray
    return configurations
  }

  // MARK: - Obtaining CoreSimulator Classes

  @objc(obtainRuntimeWithError:)
  public func obtainRuntime() throws -> SimRuntime {
    let runtimes = FBSimulatorConfiguration.supportedRuntimes()
    let matchingRuntimes = (runtimes as NSArray).filtered(using: runtimePredicate) as! [SimRuntime]
    if matchingRuntimes.isEmpty {
      throw FBSimulatorError.describe("Could not obtain matching SimRuntime, no matches. Available Runtimes \(runtimes)").build()
    }
    if matchingRuntimes.count > 1 {
      throw FBSimulatorError.describe("Matching Runtimes is ambiguous: \(matchingRuntimes)").build()
    }
    return matchingRuntimes[0]
  }

  @objc(obtainDeviceTypeWithError:)
  public func obtainDeviceType() throws -> SimDeviceType {
    let deviceTypes = FBSimulatorConfiguration.supportedDeviceTypes()
    let matchingDeviceTypes = (deviceTypes as NSArray).filtered(using: FBSimulatorConfiguration.deviceTypePredicate(device)) as! [SimDeviceType]
    if matchingDeviceTypes.isEmpty {
      throw FBSimulatorError.describe("Could not obtain matching DeviceTypes, no matches. Available Device Types \(matchingDeviceTypes)").build()
    }
    if matchingDeviceTypes.count > 1 {
      throw FBSimulatorError.describe("Matching Device Types is ambiguous: \(matchingDeviceTypes)").build()
    }
    return matchingDeviceTypes[0]
  }

  // MARK: - Private

  private class func osVersions(forRuntimes runtimes: [SimRuntime]) -> [FBOSVersion] {
    return runtimes.map { runtime in
      let name = FBOSVersionName(rawValue: runtime.name!)
      return FBiOSTargetConfiguration.nameToOSVersion[name] ?? FBOSVersion.generic(withName: runtime.name!)
    }
  }

  private class func supportedRuntimes() -> [SimRuntime] {
    return FBSimulatorServiceContext.sharedServiceContext().supportedRuntimes()
  }

  private class func supportedDeviceTypes() -> [SimDeviceType] {
    return FBSimulatorServiceContext.sharedServiceContext().supportedDeviceTypes()
  }

  private class func supportedRuntimes(forDevice device: FBDeviceType) -> [SimRuntime] {
    return supportedRuntimes()
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
    return NSCompoundPredicate(andPredicateWithSubpredicates: [
      FBSimulatorConfiguration.runtimeProductFamilyPredicate(device),
      FBSimulatorConfiguration.runtimeNamePredicate(os),
      runtimeAvailabilityPredicate,
    ])
  }

  private class func runtimeProductFamilyPredicate(_ device: FBDeviceType) -> NSPredicate {
    return NSPredicate { obj, _ in
      guard let runtime = obj as? SimRuntime else { return false }
      return (runtime.supportedProductFamilyIDs as! [NSNumber]).contains(NSNumber(value: device.family.rawValue))
    }
  }

  private class func runtimeNamePredicate(_ os: FBOSVersion) -> NSPredicate {
    return NSPredicate { obj, _ in
      guard let runtime = obj as? SimRuntime else { return false }
      return runtime.name == os.name.rawValue
    }
  }

  private var runtimeAvailabilityPredicate: NSPredicate {
    return NSPredicate { obj, _ in
      guard let runtime = obj as? SimRuntime else { return false }
      return runtime.available
    }
  }

  private class func deviceTypePredicate(_ device: FBDeviceType) -> NSPredicate {
    return NSPredicate { obj, _ in
      guard let deviceType = obj as? SimDeviceType else { return false }
      return deviceType.name == device.model.rawValue
    }
  }
}
