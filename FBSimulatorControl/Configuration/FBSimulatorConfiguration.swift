// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
@preconcurrency import Foundation

@objc(FBSimulatorConfiguration)
public final class FBSimulatorConfiguration: NSObject, NSCopying {

  // MARK: - Properties

  @objc public let device: FBDeviceType
  @objc public let os: FBOSVersion

  // MARK: - Initializers

  private init(device: FBDeviceType, os: FBOSVersion) {
    self.device = device
    self.os = os
    super.init()
  }

  // Swift compatibility alias: ObjC importer mapped `defaultConfiguration` to `default`
  public static var `default`: FBSimulatorConfiguration {
    return defaultConfiguration
  }

  @objc public nonisolated(unsafe) static let defaultConfiguration: FBSimulatorConfiguration = {
    FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworksOrAbort()
    let model = FBDeviceModel(rawValue: "iPhone 6")
    let device = FBiOSTargetConfiguration.nameToDevice[model]!
    let os = FBSimulatorConfiguration.newestAvailableOS(forDevice: device)!
    return FBSimulatorConfiguration(device: device, os: os)
  }()

  // MARK: - NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return FBSimulatorConfiguration(device: device, os: os)
  }

  // MARK: - NSObject

  public override var hash: Int {
    return device.model.rawValue.hash ^ os.name.rawValue.hash
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorConfiguration else { return false }
    return device.model == other.device.model && os.name == other.os.name
  }

  public override var description: String {
    return "Device '\(device.model.rawValue)' | OS Version '\(os.name.rawValue)'"
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
    return FBSimulatorConfiguration(device: device, os: os)
  }

  private func withDevice(_ device: FBDeviceType) -> FBSimulatorConfiguration {
    let os = self.os
    if os.families.isEmpty || os.families.contains(NSNumber(value: device.family.rawValue)) {
      return FBSimulatorConfiguration(device: device, os: os)
    }
    let newOS = FBSimulatorConfiguration.newestAvailableOS(forDevice: device) ?? os
    return FBSimulatorConfiguration(device: device, os: newOS)
  }
}
