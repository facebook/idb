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
    try _defaultConfiguration.get()
  }

  // Memoized so the default is computed (and the developer directory resolved) at most once,
  // matching the previous `static let` semantics while letting the resolution error surface.
  private nonisolated(unsafe) static let _defaultConfiguration: Result<FBSimulatorConfiguration, Error> = {
    FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworksOrAbort()
    let model = FBDeviceModel(rawValue: "iPhone 6")
    guard let device = FBiOSTargetConfiguration.nameToDevice[model] else {
      return .failure(FBSimulatorError.describe("No device type is registered for 'iPhone 6'").build())
    }
    do {
      guard let os = try FBSimulatorConfiguration.newestAvailableOS(forDevice: device) else {
        return .failure(FBSimulatorError.describe("No available OS versions for the default simulator configuration").build())
      }
      return .success(FBSimulatorConfiguration(device: device, os: os))
    } catch {
      return .failure(error)
    }
  }()

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
