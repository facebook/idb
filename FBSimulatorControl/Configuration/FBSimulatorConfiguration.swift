/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@preconcurrency import Foundation

@objc(FBSimulatorConfiguration)
public final class FBSimulatorConfiguration: NSObject, NSCopying {

  // MARK: - Properties

  @objc public let device: FBDeviceType
  @objc public let os: FBOSVersion

  // MARK: - Initializers

  // Module-internal so same-module extensions (e.g. FBSimulatorConfiguration+CoreSimulator) can build a
  // configuration directly without going through the throwing `defaultConfiguration()`. External callers
  // still construct via `defaultConfiguration()` + the `with*` methods.
  init(device: FBDeviceType, os: FBOSVersion) {
    self.device = device
    self.os = os
    super.init()
  }

  @objc
  public static func defaultConfiguration() throws -> FBSimulatorConfiguration {
    if let override = overrideLock.withLock({ defaultOverride }) {
      return override
    }
    return try _defaultConfiguration.get()
  }

  // MARK: - Default Override (fork addition)

  private static let overrideLock = NSLock()
  nonisolated(unsafe) private static var defaultOverride: FBSimulatorConfiguration?

  /**
   Overrides the default configuration at runtime.
   This is useful when the host cannot query CoreSimulator runtimes (e.g. sandboxed),
   but the caller already knows the active simulator device and OS name.
   */
  @objc(overrideDefaultConfigurationWithDeviceModel:osName:)
  public static func overrideDefaultConfiguration(withDeviceModel model: FBDeviceModel, osName: FBOSVersionName) {
    let device = FBiOSTargetConfiguration.nameToDevice[model] ?? FBDeviceType.generic(withName: model.rawValue)
    let os = FBiOSTargetConfiguration.nameToOSVersion[osName] ?? FBOSVersion.generic(withName: osName.rawValue)
    overrideLock.withLock {
      defaultOverride = FBSimulatorConfiguration(device: device, os: os)
    }
  }

  /**
   Clears any previously set default configuration override.
   */
  @objc
  public static func clearDefaultConfigurationOverride() {
    overrideLock.withLock {
      defaultOverride = nil
    }
  }

  // Memoized so the default is computed (and the developer directory resolved) at most once,
  // matching the previous `static let` semantics while letting the resolution error surface.
  private nonisolated(unsafe) static let _defaultConfiguration: Result<FBSimulatorConfiguration, Error> = {
    FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworksOrAbort()
    // Fork change: prefer the newest available iPhone Pro (then any iPhone) over
    // upstream's hardcoded "iPhone 6", which no recent Xcode ships a runtime for.
    let fallbackModel = FBDeviceModel(rawValue: "iPhone 6")
    guard let device = newestAvailableiPhoneProDevice() ?? newestAvailableiPhoneDevice() ?? FBiOSTargetConfiguration.nameToDevice[fallbackModel] else {
      return .failure(FBSimulatorConfigurationError.noDefaultDeviceTypeRegistered(model: fallbackModel.rawValue))
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

  // MARK: - Device Selection (fork addition)

  private static func deviceModelGeneration(fromName name: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: "iPhone\\s+(\\d+)"),
      let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
      match.numberOfRanges >= 2,
      let range = Range(match.range(at: 1), in: name)
    else {
      return -1
    }
    return Int(name[range]) ?? -1
  }

  private static func deviceModelProRank(fromName name: String) -> Int {
    if name.contains("Pro Max") {
      return 2
    }
    if name.contains("Pro") {
      return 1
    }
    return 0
  }

  private static func isDeviceNameOrderedBefore(_ left: String, _ right: String) -> Bool {
    let leftGeneration = deviceModelGeneration(fromName: left)
    let rightGeneration = deviceModelGeneration(fromName: right)
    if leftGeneration != rightGeneration {
      if leftGeneration == -1 {
        return true
      }
      if rightGeneration == -1 {
        return false
      }
      return leftGeneration < rightGeneration
    }
    let leftRank = deviceModelProRank(fromName: left)
    let rightRank = deviceModelProRank(fromName: right)
    if leftRank != rightRank {
      return leftRank < rightRank
    }
    return left.compare(right, options: .numeric) == .orderedAscending
  }

  private static func newestAvailableDevice(matching predicate: (String) -> Bool) -> FBDeviceType? {
    guard let serviceContext = try? FBSimulatorServiceContext.sharedServiceContext() else {
      return nil
    }
    var devices: [FBDeviceType] = []
    for deviceType in serviceContext.supportedDeviceTypes() {
      guard predicate(deviceType.name) else {
        continue
      }
      if let device = FBiOSTargetConfiguration.nameToDevice[FBDeviceModel(rawValue: deviceType.name)] {
        devices.append(device)
      }
    }
    return devices.sorted { isDeviceNameOrderedBefore($0.model.rawValue, $1.model.rawValue) }.last
  }

  private static func newestAvailableiPhoneProDevice() -> FBDeviceType? {
    newestAvailableDevice { $0.contains("iPhone") && $0.contains("Pro") }
  }

  private static func newestAvailableiPhoneDevice() -> FBDeviceType? {
    newestAvailableDevice { $0.contains("iPhone") }
  }

  // MARK: - NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    FBSimulatorConfiguration(device: device, os: os)
  }

  // MARK: - NSObject

  public override var hash: Int {
    device.model.rawValue.hash ^ os.name.rawValue.hash
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorConfiguration else { return false }
    return device.model == other.device.model && os.name == other.os.name
  }

  public override var description: String {
    "Device '\(device.model.rawValue)' | OS Version '\(os.name.rawValue)'"
  }

  // MARK: - Models

  @objc
  public func withDeviceModel(_ model: FBDeviceModel) -> FBSimulatorConfiguration {
    let device = FBiOSTargetConfiguration.nameToDevice[model] ?? FBDeviceType.generic(withName: model.rawValue)
    return withDevice(device)
  }

  // MARK: - OS Versions

  @objc
  public func withOSNamed(_ osName: FBOSVersionName) -> FBSimulatorConfiguration {
    let os = FBiOSTargetConfiguration.nameToOSVersion[osName] ?? FBOSVersion.generic(withName: osName.rawValue)
    return withOS(os)
  }

  // MARK: - Private

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
