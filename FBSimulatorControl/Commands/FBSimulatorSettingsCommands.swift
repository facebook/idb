/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// An enumeration of simulator settings that can be toggled on/off.
/// Each value maps to a different underlying transport (SimDevice API, Darwin notification, etc.)
/// but the public API is uniform: setSetting:enabled:.
@objc public enum FBSimulatorSetting: UInt {
  case hardwareKeyboard
  case slowAnimations
  case increaseContrast
}

/// Dark/Light mode appearance.
/// Values match UIUserInterfaceStyle used by SimDevice's setUIInterfaceStyle:error:.
@objc public enum FBSimulatorAppearance: Int {
  case light = 1 // UIUserInterfaceStyleLight
  case dark = 2 // UIUserInterfaceStyleDark
}

/// Dynamic Type content size categories.
/// Values match the integer indices used by SimDevice's setContentSizeCategory:error:.
@objc public enum FBSimulatorContentSizeCategory: Int {
  case extraSmall = 1
  case small = 2
  case medium = 3
  case large = 4
  case extraLarge = 5
  case extraExtraLarge = 6
  case extraExtraExtraLarge = 7
  case accessibilityMedium = 8
  case accessibilityLarge = 9
  case accessibilityExtraLarge = 10
  case accessibilityExtraExtraLarge = 11
  case accessibilityExtraExtraExtraLarge = 12
}

private let slowAnimationsNotification = "com.apple.UIKit.SimulatorSlowMotionAnimationState"

@objc public protocol FBSimulatorSettingsCommandsProtocol: NSObjectProtocol, FBiOSTargetCommand {
  @objc(setSetting:enabled:)
  func setSetting(_ setting: FBSimulatorSetting, enabled: Bool) -> FBFuture<NSNull>

  func currentAppearance() -> FBFuture<NSNumber>

  @objc(setAppearance:)
  func setAppearance(_ appearance: FBSimulatorAppearance) -> FBFuture<NSNull>

  func currentContentSizeCategory() -> FBFuture<NSNumber>

  @objc(setContentSizeCategory:)
  func setContentSizeCategory(_ category: FBSimulatorContentSizeCategory) -> FBFuture<NSNull>

  func currentStatusBarOverrides() -> FBFuture<FBStatusBarOverride>

  @objc(overrideStatusBar:)
  func overrideStatusBar(_ override: FBStatusBarOverride?) -> FBFuture<NSNull>

  @objc(setPreference:value:type:domain:)
  func setPreference(_ name: String, value: String, type: String?, domain: String?) -> FBFuture<NSNull>

  @objc(getCurrentPreference:domain:)
  func getCurrentPreference(_ name: String, domain: String?) -> FBFuture<NSString>

  @objc(grantAccess:toServices:)
  func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) -> FBFuture<NSNull>

  @objc(revokeAccess:toServices:)
  func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) -> FBFuture<NSNull>

  @objc(grantAccess:toDeeplink:)
  func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) -> FBFuture<NSNull>

  @objc(revokeAccess:toDeeplink:)
  func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) -> FBFuture<NSNull>

  @objc(updateContacts:)
  func updateContacts(_ databaseDirectory: String) -> FBFuture<NSNull>

  func clearContacts() -> FBFuture<NSNull>

  func clearPhotos() -> FBFuture<NSNull>

  @objc(setProxyWithHost:port:type:)
  func setProxy(host: String, port: UInt, type: String) -> FBFuture<NSNull>

  func clearProxy() -> FBFuture<NSNull>

  func listProxy() -> FBFuture<NSString>

  @objc(setDnsServers:)
  func setDnsServers(_ servers: [String]) -> FBFuture<NSNull>

  func clearDns() -> FBFuture<NSNull>

  func listDns() -> FBFuture<NSString>

  @objc(setHealthAuthorization:forBundleID:typeIdentifiers:)
  func setHealthAuthorization(_ approved: Bool, forBundleID bundleID: String, typeIdentifiers: [String]) -> FBFuture<NSNull>

  @objc(clearHealthAuthorizationForBundleID:)
  func clearHealthAuthorization(forBundleID bundleID: String) -> FBFuture<NSNull>

  @objc(listHealthAuthorizationForBundleID:)
  func listHealthAuthorization(forBundleID bundleID: String) -> FBFuture<NSString>
}

@objc(FBSimulatorSettingsCommands)
public final class FBSimulatorSettingsCommands: NSObject, FBSimulatorSettingsCommandsProtocol {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorSettingsCommands {
    return FBSimulatorSettingsCommands(simulator: target as! FBSimulator)
  }

  internal init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Public (legacy FBFuture entry points)

  @objc(setSetting:enabled:)
  public func setSetting(_ setting: FBSimulatorSetting, enabled: Bool) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await setSettingAsync(setting, enabled: enabled)
      return NSNull()
    }
  }

  // Single source of truth for setSetting dispatch. Both the FBFuture entry point
  // and the AsyncSettingsCommands async entry point call into this.
  fileprivate func setSettingAsync(_ setting: FBSimulatorSetting, enabled: Bool) async throws {
    switch setting {
    case .hardwareKeyboard:
      try await setHardwareKeyboardEnabledAsync(enabled)
    case .slowAnimations:
      try await setSlowAnimationsEnabledAsync(enabled)
    case .increaseContrast:
      try await setIncreaseContrastEnabledAsync(enabled)
    }
  }

  @objc
  public func currentAppearance() -> FBFuture<NSNumber> {
    fbFutureFromAsync { [self] in
      try await currentAppearanceAsync().rawValue as NSNumber
    }
  }

  fileprivate func currentAppearanceAsync() async throws -> FBSimulatorAppearance {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let raw = simulator.device.currentUIInterfaceStyle()
    return FBSimulatorAppearance(rawValue: raw) ?? .light
  }

  @objc(setAppearance:)
  public func setAppearance(_ appearance: FBSimulatorAppearance) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await setAppearanceAsync(appearance)
      return NSNull()
    }
  }

  fileprivate func setAppearanceAsync(_ appearance: FBSimulatorAppearance) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try simulator.device.setUIInterfaceStyle(appearance.rawValue)
  }

  @objc
  public func currentContentSizeCategory() -> FBFuture<NSNumber> {
    fbFutureFromAsync { [self] in
      try await currentContentSizeCategoryAsync().rawValue as NSNumber
    }
  }

  fileprivate func currentContentSizeCategoryAsync() async throws -> FBSimulatorContentSizeCategory {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let raw = simulator.device.currentContentSizeCategory()
    return FBSimulatorContentSizeCategory(rawValue: raw) ?? .large
  }

  @objc(setContentSizeCategory:)
  public func setContentSizeCategory(_ category: FBSimulatorContentSizeCategory) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await setContentSizeCategoryAsync(category)
      return NSNull()
    }
  }

  fileprivate func setContentSizeCategoryAsync(_ category: FBSimulatorContentSizeCategory) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try simulator.device.setContentSizeCategory(category.rawValue)
  }

  @objc
  public func currentStatusBarOverrides() -> FBFuture<FBStatusBarOverride> {
    fbFutureFromAsync { [self] in
      try await currentStatusBarOverridesAsync()
    }
  }

  fileprivate func currentStatusBarOverridesAsync() async throws -> FBStatusBarOverride {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    var timeString: NSString?
    var dataNetworkType: NSNumber?
    var wiFiMode: NSNumber?
    var wiFiBars: NSNumber?
    var cellularMode: NSNumber?
    var operatorName: NSString?
    var cellularBars: NSNumber?
    var batteryState: NSNumber?
    var batteryLevel: NSNumber?
    var showNotCharging: NSNumber?
    try simulator.device.currentStatusBarOverrides(
      forTime: &timeString,
      dataNetworkType: &dataNetworkType,
      wiFiMode: &wiFiMode,
      wiFiBars: &wiFiBars,
      cellularMode: &cellularMode,
      operatorName: &operatorName,
      cellularBars: &cellularBars,
      batteryState: &batteryState,
      batteryLevel: &batteryLevel,
      showNotCharging: &showNotCharging)
    let override = FBStatusBarOverride()
    override.timeString = timeString as String?
    override.dataNetworkType = dataNetworkType
    override.wiFiMode = wiFiMode
    override.wiFiBars = wiFiBars
    override.cellularMode = cellularMode
    override.cellularBars = cellularBars
    override.operatorName = operatorName as String?
    override.batteryState = batteryState
    override.batteryLevel = batteryLevel
    override.showNotCharging = showNotCharging
    return override
  }

  @objc(overrideStatusBar:)
  public func overrideStatusBar(_ override: FBStatusBarOverride?) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await overrideStatusBarAsync(override)
      return NSNull()
    }
  }

  fileprivate func overrideStatusBarAsync(_ override: FBStatusBarOverride?) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    guard let override else {
      // clearStatusBarOverrides:(NSUInteger)flags sends @{@"OverridesToClear": @(flags)} via MIG.
      // Bit 31 (0x80000000) = clear all. Pass NSUIntegerMax to clear everything.
      try simulator.device.clearStatusBarOverrides(UInt.max)
      return
    }
    if let timeString = override.timeString {
      try simulator.device.overrideStatusBarTime(timeString)
    }
    if let dataNetworkType = override.dataNetworkType {
      try simulator.device.overrideStatusBarDataNetworkType(dataNetworkType.intValue)
    }
    if override.wiFiMode != nil || override.wiFiBars != nil {
      let mode = override.wiFiMode?.intValue ?? 3
      let bars = override.wiFiBars?.intValue ?? 3
      try simulator.device.overrideStatusBarWiFiMode(mode, bars: bars)
    }
    if override.cellularMode != nil || override.operatorName != nil || override.cellularBars != nil {
      let mode = override.cellularMode?.intValue ?? 3
      let name = override.operatorName ?? ""
      let bars = override.cellularBars?.intValue ?? 4
      try simulator.device.overrideStatusBarCellularMode(mode, operatorName: name, bars: bars)
    }
    if override.batteryState != nil || override.batteryLevel != nil || override.showNotCharging != nil {
      let state = override.batteryState?.intValue ?? 2
      let level = override.batteryLevel?.intValue ?? 100
      let notCharging = override.showNotCharging?.boolValue ?? false
      try simulator.device.overrideStatusBarBatteryState(state, batteryLevel: level, showNotCharging: notCharging)
    }
  }

  @objc
  public func setPreference(_ name: String, value: String, type: String?, domain: String?) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await setPreferenceAsync(name, value: value, type: type, domain: domain)
      return NSNull()
    }
  }

  @objc
  public func getCurrentPreference(_ name: String, domain: String?) -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await getCurrentPreferenceAsync(name, domain: domain) as NSString
    }
  }

  @objc
  public func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await grantAccessAsync(bundleIDs, toServices: services)
      return NSNull()
    }
  }

  @objc
  public func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await revokeAccessAsync(bundleIDs, toServices: services)
      return NSNull()
    }
  }

  @objc
  public func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await grantAccessAsync(bundleIDs, toDeeplink: scheme)
      return NSNull()
    }
  }

  @objc
  public func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await revokeAccessAsync(bundleIDs, toDeeplink: scheme)
      return NSNull()
    }
  }

  @objc
  public func updateContacts(_ databaseDirectory: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await updateContactsAsync(databaseDirectory)
      return NSNull()
    }
  }

  @objc
  public func clearContacts() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(withService: "contacts", action: "clear")
      return NSNull()
    }
  }

  @objc
  public func clearPhotos() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(withService: "photos", action: "clear")
      return NSNull()
    }
  }

  @objc(setProxyWithHost:port:type:)
  public func setProxy(host: String, port: UInt, type: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(
        withService: "proxy",
        action: "set",
        arguments: [host, "\(port)", type.isEmpty ? "http" : type])
      return NSNull()
    }
  }

  @objc
  public func clearProxy() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(withService: "proxy", action: "clear")
      return NSNull()
    }
  }

  @objc
  public func listProxy() -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(withService: "proxy", action: "list") as NSString
    }
  }

  @objc(setDnsServers:)
  public func setDnsServers(_ servers: [String]) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      if servers.isEmpty {
        throw FBSimulatorError.describe("At least one DNS server address is required").build()
      }
      try await runSimulatorFrameworkBridgeAsync(withService: "dns", action: "set", arguments: servers)
      return NSNull()
    }
  }

  @objc
  public func clearDns() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(withService: "dns", action: "clear")
      return NSNull()
    }
  }

  @objc
  public func listDns() -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(withService: "dns", action: "list") as NSString
    }
  }

  @objc(setHealthAuthorization:forBundleID:typeIdentifiers:)
  public func setHealthAuthorization(_ approved: Bool, forBundleID bundleID: String, typeIdentifiers: [String]) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      let action = approved ? "approve" : "revoke"
      let args = [bundleID] + typeIdentifiers
      try await runSimulatorFrameworkBridgeAsync(withService: "health", action: action, arguments: args)
      return NSNull()
    }
  }

  @objc(clearHealthAuthorizationForBundleID:)
  public func clearHealthAuthorization(forBundleID bundleID: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(withService: "health", action: "clear", arguments: [bundleID])
      return NSNull()
    }
  }

  @objc(listHealthAuthorizationForBundleID:)
  public func listHealthAuthorization(forBundleID bundleID: String) -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await runSimulatorFrameworkBridgeAsync(withService: "health", action: "list", arguments: [bundleID]) as NSString
    }
  }

  // MARK: - Async

  fileprivate func setHardwareKeyboardEnabledAsync(_ enabled: Bool) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try simulator.device.setHardwareKeyboardEnabled(enabled, keyboardType: 0)
  }

  fileprivate func setSlowAnimationsEnabledAsync(_ enabled: Bool) async throws {
    try await setDarwinNotificationStateAsync(enabled, name: slowAnimationsNotification)
  }

  fileprivate func setIncreaseContrastEnabledAsync(_ enabled: Bool) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try simulator.device.setIncreaseContrastEnabled(enabled)
  }

  fileprivate func setDarwinNotificationStateAsync(_ enabled: Bool, name: String) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try simulator.device.darwinNotificationSetState(enabled ? 1 : 0, name: name)
    try simulator.device.postDarwinNotification(name)
  }

  fileprivate func setPreferenceAsync(_ name: String, value: String, type: String?, domain: String?) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await bridgeFBFutureVoid(
      FBPreferenceModificationStrategy(simulator: simulator)
        .setPreference(name, value: value, type: type, domain: domain))
  }

  fileprivate func getCurrentPreferenceAsync(_ name: String, domain: String?) async throws -> String {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let result = try await bridgeFBFuture(
      FBPreferenceModificationStrategy(simulator: simulator)
        .getCurrentPreference(name, domain: domain))
    return result as String
  }

  fileprivate func grantAccessAsync(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    if services.isEmpty {
      throw FBSimulatorError.describe("Cannot approve any services for \(bundleIDs) since no services were provided").build()
    }
    if bundleIDs.isEmpty {
      throw FBSimulatorError.describe("Cannot approve \(services) since no bundle ids were provided").build()
    }

    var toApprove = services
    let iosVer = simulator.osVersion
    let coreSimulatorSettingMapping: [FBTargetSettingsService: String]

    if iosVer.version.majorVersion >= 13 {
      coreSimulatorSettingMapping = FBSimulatorSettingsCommands.coreSimulatorSettingMappingPostIos13
    } else {
      coreSimulatorSettingMapping = FBSimulatorSettingsCommands.coreSimulatorSettingMappingPreIos13
    }

    if simulator.device.responds(to: NSSelectorFromString("setPrivacyAccessForService:bundleID:granted:error:")) {
      let simDeviceServices = toApprove.intersection(Set(coreSimulatorSettingMapping.keys))
      if !simDeviceServices.isEmpty {
        var internalServices = Set<String>()
        for service in simDeviceServices {
          if let internalService = coreSimulatorSettingMapping[service] {
            internalServices.insert(internalService)
          }
        }
        toApprove.subtract(simDeviceServices)
        try coreSimulatorApprove(withBundleIDs: bundleIDs, toServices: internalServices)
      }
    }
    if !toApprove.isEmpty && !toApprove.isDisjoint(with: Set(FBSimulatorSettingsCommands.tccDatabaseMapping.keys)) {
      let tccServices = toApprove.intersection(Set(FBSimulatorSettingsCommands.tccDatabaseMapping.keys))
      toApprove.subtract(tccServices)
      try await modifyTCCDatabaseAsync(withBundleIDs: bundleIDs, toServices: tccServices, grantAccess: true)
    }
    if !toApprove.isEmpty && toApprove.contains(FBTargetSettingsService.location) {
      try await authorizeLocationSettingsAsync(Array(bundleIDs))
      toApprove.remove(FBTargetSettingsService.location)
    }
    if !toApprove.isEmpty && toApprove.contains(FBTargetSettingsService(rawValue: "notification")) {
      try await updateNotificationServiceAsync(Array(bundleIDs), approve: true)
      toApprove.remove(FBTargetSettingsService(rawValue: "notification"))
    }
    if !toApprove.isEmpty && toApprove.contains(FBTargetSettingsService(rawValue: "health")) {
      try await updateHealthServiceAsync(Array(bundleIDs), approve: true)
      toApprove.remove(FBTargetSettingsService(rawValue: "health"))
    }

    if !toApprove.isEmpty {
      throw FBSimulatorError.describe("Cannot approve \(FBCollectionInformation.oneLineDescription(from: Array(toApprove))) since there is no handling of it").build()
    }
  }

  fileprivate func revokeAccessAsync(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    if services.isEmpty {
      throw FBSimulatorError.describe("Cannot revoke any services for \(bundleIDs) since no services were provided").build()
    }
    if bundleIDs.isEmpty {
      throw FBSimulatorError.describe("Cannot revoke \(services) since no bundle ids were provided").build()
    }

    var toRevoke = services
    let iosVer = simulator.osVersion
    let coreSimulatorSettingMapping: [FBTargetSettingsService: String]

    if iosVer.version.majorVersion >= 13 {
      coreSimulatorSettingMapping = FBSimulatorSettingsCommands.coreSimulatorSettingMappingPostIos13
    } else {
      coreSimulatorSettingMapping = FBSimulatorSettingsCommands.coreSimulatorSettingMappingPreIos13
    }

    if simulator.device.responds(to: NSSelectorFromString("setPrivacyAccessForService:bundleID:granted:error:")) {
      let simDeviceServices = toRevoke.intersection(Set(coreSimulatorSettingMapping.keys))
      if !simDeviceServices.isEmpty {
        var internalServices = Set<String>()
        for service in simDeviceServices {
          if let internalService = coreSimulatorSettingMapping[service] {
            internalServices.insert(internalService)
          }
        }
        toRevoke.subtract(simDeviceServices)
        try coreSimulatorRevoke(withBundleIDs: bundleIDs, toServices: internalServices)
      }
    }
    if !toRevoke.isEmpty && !toRevoke.isDisjoint(with: Set(FBSimulatorSettingsCommands.tccDatabaseMapping.keys)) {
      let tccServices = toRevoke.intersection(Set(FBSimulatorSettingsCommands.tccDatabaseMapping.keys))
      toRevoke.subtract(tccServices)
      try await modifyTCCDatabaseAsync(withBundleIDs: bundleIDs, toServices: tccServices, grantAccess: false)
    }
    if !toRevoke.isEmpty && toRevoke.contains(FBTargetSettingsService.location) {
      try await revokeLocationSettingsAsync(Array(bundleIDs))
      toRevoke.remove(FBTargetSettingsService.location)
    }
    if !toRevoke.isEmpty && toRevoke.contains(FBTargetSettingsService(rawValue: "notification")) {
      try await updateNotificationServiceAsync(Array(bundleIDs), approve: false)
      toRevoke.remove(FBTargetSettingsService(rawValue: "notification"))
    }
    if !toRevoke.isEmpty && toRevoke.contains(FBTargetSettingsService(rawValue: "health")) {
      try await updateHealthServiceAsync(Array(bundleIDs), approve: false)
      toRevoke.remove(FBTargetSettingsService(rawValue: "health"))
    }

    if !toRevoke.isEmpty {
      throw FBSimulatorError.describe("Cannot revoke \(FBCollectionInformation.oneLineDescription(from: Array(toRevoke))) since there is no handling of it").build()
    }
  }

  fileprivate func grantAccessAsync(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    if scheme.isEmpty {
      throw FBSimulatorError.describe("Empty scheme provided to url approve").build()
    }
    if bundleIDs.isEmpty {
      throw FBSimulatorError.describe("Empty bundleID set provided to url approve").build()
    }

    let preferencesDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Library/Preferences")
    let schemeApprovalPlistPath = (preferencesDirectory as NSString).appendingPathComponent("com.apple.launchservices.schemeapproval.plist")

    var schemeApprovalProperties: NSMutableDictionary = NSMutableDictionary()
    if FileManager.default.fileExists(atPath: schemeApprovalPlistPath) {
      guard let dict = NSDictionary(contentsOfFile: schemeApprovalPlistPath)?.mutableCopy() as? NSMutableDictionary else {
        throw FBSimulatorError.describe("Failed to read the file at \(schemeApprovalPlistPath)").build()
      }
      schemeApprovalProperties = dict
    }

    let urlKey = FBSimulatorSettingsCommands.magicDeeplinkKey(forScheme: scheme)
    for bundleID in bundleIDs {
      schemeApprovalProperties[urlKey] = bundleID
    }

    do {
      try FileManager.default.createDirectory(atPath: preferencesDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw FBSimulatorError.describe("Failed to create folders for scheme approval plist").build()
    }
    if !schemeApprovalProperties.write(toFile: schemeApprovalPlistPath, atomically: true) {
      throw FBSimulatorError.describe("Failed to write scheme approval plist").build()
    }
  }

  fileprivate func revokeAccessAsync(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    if scheme.isEmpty {
      throw FBSimulatorError.describe("Empty scheme provided to url revoke").build()
    }
    if bundleIDs.isEmpty {
      throw FBSimulatorError.describe("Empty bundleID set provided to url revoke").build()
    }

    let preferencesDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Library/Preferences")
    let schemeApprovalPlistPath = (preferencesDirectory as NSString).appendingPathComponent("com.apple.launchservices.schemeapproval.plist")

    guard FileManager.default.fileExists(atPath: schemeApprovalPlistPath) else {
      return
    }
    guard let schemeApprovalProperties = NSDictionary(contentsOfFile: schemeApprovalPlistPath)?.mutableCopy() as? NSMutableDictionary else {
      throw FBSimulatorError.describe("Failed to read the file at \(schemeApprovalPlistPath)").build()
    }

    let urlKey = FBSimulatorSettingsCommands.magicDeeplinkKey(forScheme: scheme)
    schemeApprovalProperties.removeObject(forKey: urlKey)

    if !schemeApprovalProperties.write(toFile: schemeApprovalPlistPath, atomically: true) {
      throw FBSimulatorError.describe("Failed to write scheme approval plist").build()
    }
  }

  fileprivate func updateContactsAsync(_ databaseDirectory: String) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let destinationDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Library/AddressBook")
    if !FileManager.default.fileExists(atPath: destinationDirectory) {
      throw FBSimulatorError.describe("Expected Address Book path to exist at \(destinationDirectory) but it was not there").build()
    }

    let sourceFilePaths = try FBSimulatorSettingsCommands.contactsDatabaseFilePaths(fromContainingDirectory: databaseDirectory)

    for sourceFilePath in sourceFilePaths {
      let destinationFilePath = (destinationDirectory as NSString).appendingPathComponent((sourceFilePath as NSString).lastPathComponent)
      if FileManager.default.fileExists(atPath: destinationFilePath) {
        try FileManager.default.removeItem(atPath: destinationFilePath)
      }
      try FileManager.default.copyItem(atPath: sourceFilePath, toPath: destinationFilePath)
    }
  }

  // MARK: - Private

  @discardableResult
  fileprivate func runSimulatorFrameworkBridgeAsync(withService service: String, action: String, arguments: [String] = []) async throws -> String {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    guard let helperPath = Bundle(for: FBSimulatorSettingsCommands.self).path(forResource: "SimulatorFrameworkBridge", ofType: nil) else {
      throw FBSimulatorError.describe("SimulatorFrameworkBridge binary not found in bundle resources. Ensure FBSimulatorControl was built correctly.").build()
    }
    if !FileManager.default.fileExists(atPath: helperPath) {
      throw FBSimulatorError.describe("SimulatorFrameworkBridge binary found in bundle but does not exist at path: \(helperPath)").build()
    }
    let spawnArguments = [helperPath, service, action] + arguments
    let runFuture =
      simulator.simctlExecutor.taskBuilder(withCommand: "spawn", arguments: spawnArguments)
      .withStdOutInMemoryAsString()
      .runUntilCompletion(withAcceptableExitCodes: [0])
    let task = try await bridgeFBFuture(runFuture)
    simulator.logger?.log("SimulatorFrameworkBridge \(service) \(action) completed successfully")
    return (task.stdOut as String?) ?? ""
  }

  fileprivate func authorizeLocationSettingsAsync(_ bundleIDs: [String]) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await bridgeFBFutureVoid(
      FBLocationServicesModificationStrategy(simulator: simulator)
        .approveLocationServices(forBundleIDs: bundleIDs))
  }

  fileprivate func revokeLocationSettingsAsync(_ bundleIDs: [String]) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await bridgeFBFutureVoid(
      FBLocationServicesModificationStrategy(simulator: simulator)
        .revokeLocationServices(forBundleIDs: bundleIDs))
  }

  fileprivate func updateHealthServiceAsync(_ bundleIDs: [String], approve approved: Bool) async throws {
    if bundleIDs.isEmpty {
      throw FBSimulatorError.describe("Empty bundleID set provided to health approve").build()
    }
    let action = approved ? "approve" : "revoke"
    for bundleID in bundleIDs {
      try await runSimulatorFrameworkBridgeAsync(withService: "health", action: action, arguments: [bundleID])
    }
  }

  fileprivate func updateNotificationServiceAsync(_ bundleIDs: [String], approve approved: Bool) async throws {
    if bundleIDs.isEmpty {
      throw FBSimulatorError.describe("Empty bundleID set provided to notifications approve").build()
    }

    let action = approved ? "approve" : "revoke"
    for bundleID in bundleIDs {
      try await runSimulatorFrameworkBridgeAsync(withService: "notifications", action: action, arguments: [bundleID])
    }
  }

  fileprivate func modifyTCCDatabaseAsync(withBundleIDs bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>, grantAccess: Bool) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    guard let dataDirectory = simulator.dataDirectory else {
      throw FBSimulatorError.describe("Simulator has no data directory").build()
    }
    let databasePath = (dataDirectory as NSString).appendingPathComponent("Library/TCC/TCC.db")
    var isDirectory: ObjCBool = true
    if !FileManager.default.fileExists(atPath: databasePath, isDirectory: &isDirectory) {
      throw FBSimulatorError.describe("Expected file to exist at path \(databasePath) but it was not there").build()
    }
    if isDirectory.boolValue {
      throw FBSimulatorError.describe("Expected file to exist at path \(databasePath) but it is a directory").build()
    }
    if !FileManager.default.isWritableFile(atPath: databasePath) {
      throw FBSimulatorError.describe("Database file at path \(databasePath) is not writable").build()
    }

    let logger = simulator.logger?.withName("sqlite_auth")
    let queue = simulator.asyncQueue

    if grantAccess {
      try await grantAccessInTCCDatabaseAsync(databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger)
    } else {
      try await revokeAccessInTCCDatabaseAsync(databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger)
    }
  }

  fileprivate func coreSimulatorApprove(withBundleIDs bundleIDs: Set<String>, toServices services: Set<String>) throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    for bundleID in bundleIDs {
      for internalService in services {
        try simulator.device.setPrivacyAccessForService(internalService, bundleID: bundleID, granted: true)
      }
    }
  }

  fileprivate func coreSimulatorRevoke(withBundleIDs bundleIDs: Set<String>, toServices services: Set<String>) throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    for bundleID in bundleIDs {
      for internalService in services {
        try simulator.device.resetPrivacyAccess(forService: internalService, bundleID: bundleID)
      }
    }
  }

  private static let tccDatabaseMapping: [FBTargetSettingsService: String] = [
    FBTargetSettingsService.contacts: "kTCCServiceAddressBook",
    FBTargetSettingsService.photos: "kTCCServicePhotos",
    FBTargetSettingsService.camera: "kTCCServiceCamera",
    FBTargetSettingsService.microphone: "kTCCServiceMicrophone",
  ]

  private static let coreSimulatorSettingMappingPreIos13: [FBTargetSettingsService: String] = [
    FBTargetSettingsService.contacts: "kTCCServiceContactsFull",
    FBTargetSettingsService.photos: "kTCCServicePhotos",
    FBTargetSettingsService.camera: "camera",
    FBTargetSettingsService.location: "__CoreLocationAlways",
    FBTargetSettingsService.microphone: "kTCCServiceMicrophone",
  ]

  private static let coreSimulatorSettingMappingPostIos13: [FBTargetSettingsService: String] = [
    FBTargetSettingsService.location: "__CoreLocationAlways"
  ]

  private static let permissibleAddressBookDBFilenames: Set<String> = [
    "AddressBook.sqlitedb",
    "AddressBook.sqlitedb-shm",
    "AddressBook.sqlitedb-wal",
    "AddressBookImages.sqlitedb",
    "AddressBookImages.sqlitedb-shm",
    "AddressBookImages.sqlitedb-wal",
  ]

  internal class func filteredTCCApprovals(_ approvals: Set<FBTargetSettingsService>) -> Set<FBTargetSettingsService> {
    return approvals.intersection(Set(tccDatabaseMapping.keys))
  }

  fileprivate func grantAccessInTCCDatabaseAsync(_ databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) async throws {
    let rows = try await FBSimulatorSettingsCommands.buildRowsAsync(forDatabase: databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger)
    _ = try await FBSimulatorSettingsCommands.runSqliteCommandAsync(onDatabase: databasePath, arguments: ["INSERT or REPLACE INTO access VALUES \(rows)"], queue: queue, logger: logger)
  }

  fileprivate func revokeAccessInTCCDatabaseAsync(_ databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) async throws {
    var deletions: [String] = []
    for bundleID in bundleIDs {
      for service in FBSimulatorSettingsCommands.filteredTCCApprovals(services) {
        let serviceName = FBSimulatorSettingsCommands.tccDatabaseMapping[service]!
        deletions.append("(service = '\(serviceName)' AND client = '\(bundleID)')")
      }
    }
    if deletions.isEmpty {
      return
    }
    _ = try await FBSimulatorSettingsCommands.runSqliteCommandAsync(
      onDatabase: databasePath,
      arguments: ["DELETE FROM access WHERE \(deletions.joined(separator: " OR "))"],
      queue: queue,
      logger: logger)
  }

  fileprivate class func buildRowsAsync(forDatabase databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) async throws -> String {
    let result = try await runSqliteCommandAsync(onDatabase: databasePath, arguments: [".schema access"], queue: queue, logger: logger)
    if result.contains("last_reminded") {
      return postiOS17ApprovalRows(forBundleIDs: bundleIDs, services: services)
    } else if result.contains("auth_value") {
      return postiOS15ApprovalRows(forBundleIDs: bundleIDs, services: services)
    } else if result.contains("last_modified") {
      return postiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    } else {
      return preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    }
  }

  internal class func preiOS12ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for service in filteredTCCApprovals(services) {
        let serviceName = tccDatabaseMapping[service]!
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 1, 0, 0, 0)")
      }
    }
    return tuples.joined(separator: ", ")
  }

  internal class func postiOS12ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    let timestamp = UInt(Date().timeIntervalSince1970)
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for service in filteredTCCApprovals(services) {
        let serviceName = tccDatabaseMapping[service]!
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 1, 1, NULL, NULL, NULL, 'UNUSED', NULL, NULL, \(timestamp))")
      }
    }
    return tuples.joined(separator: ", ")
  }

  internal class func postiOS15ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    let timestamp = UInt(Date().timeIntervalSince1970)
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for service in filteredTCCApprovals(services) {
        let serviceName = tccDatabaseMapping[service]!
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 2, 2, 2, NULL, NULL, NULL, 'UNUSED', NULL, NULL, \(timestamp))")
      }
    }
    return tuples.joined(separator: ", ")
  }

  internal class func postiOS17ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    let timestamp = UInt(Date().timeIntervalSince1970)
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for service in filteredTCCApprovals(services) {
        let serviceName = tccDatabaseMapping[service]!
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 2, 2, 2, NULL, NULL, NULL, 'UNUSED', NULL, NULL, \(timestamp), NULL, NULL, 'UNUSED', \(timestamp))")
      }
    }
    return tuples.joined(separator: ", ")
  }

  fileprivate class func runSqliteCommandAsync(onDatabase databasePath: String, arguments: [String], queue: DispatchQueue, logger: (any FBControlCoreLogger)?) async throws -> String {
    let allArguments = [databasePath] + arguments
    logger?.log("Running sqlite3 \(FBCollectionInformation.oneLineDescription(from: allArguments))")
    let runFuture = FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/usr/bin/sqlite3", arguments: allArguments)
      .withStdOutInMemoryAsString()
      .withStdErrInMemoryAsString()
      .withTaskLifecycleLogging(to: logger)
      .runUntilCompletion(withAcceptableExitCodes: [0, 1])
    let task = try await bridgeFBFuture(runFuture)
    if task.exitCode.result != 0 as NSNumber {
      throw FBSimulatorError.describe("Task did not exit 0: \(task.exitCode.result ?? 0) \(task.stdOut ?? "") \(task.stdErr ?? "")").build()
    }
    if let stdErr = task.stdErr as? String, stdErr.hasPrefix("Error") {
      throw FBSimulatorError.describe("Failed to execute sqlite command: \(stdErr)").build()
    }
    return (task.stdOut as String?) ?? ""
  }

  private class func contactsDatabaseFilePaths(fromContainingDirectory databaseDirectory: String) throws -> [String] {
    var filePaths: [String] = []
    guard let enumerator = FileManager.default.enumerator(atPath: databaseDirectory) else {
      throw FBSimulatorError.describe("Could not enumerate directory at \(databaseDirectory)").build()
    }

    for case let path as String in enumerator {
      if !permissibleAddressBookDBFilenames.contains((path as NSString).lastPathComponent) {
        continue
      }
      let fullPath = (databaseDirectory as NSString).appendingPathComponent(path)
      filePaths.append(fullPath)
    }

    if filePaths.isEmpty {
      throw FBSimulatorError.describe("Could not update Address Book DBs when no databases are provided").build()
    }

    return filePaths
  }

  internal class func magicDeeplinkKey(forScheme scheme: String) -> String {
    return "com.apple.CoreSimulator.CoreSimulatorBridge-->\(scheme)"
  }
}

// MARK: - AsyncSettingsCommands

extension FBSimulatorSettingsCommands: AsyncSettingsCommands {

  public func setSetting(_ setting: FBSimulatorSetting, enabled: Bool) async throws {
    try await setSettingAsync(setting, enabled: enabled)
  }

  public func setPreference(_ name: String, value: String, type: String?, domain: String?) async throws {
    try await setPreferenceAsync(name, value: value, type: type, domain: domain)
  }

  public func getCurrentPreference(_ name: String, domain: String?) async throws -> String {
    return try await getCurrentPreferenceAsync(name, domain: domain)
  }

  public func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    try await grantAccessAsync(bundleIDs, toServices: services)
  }

  public func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    try await revokeAccessAsync(bundleIDs, toServices: services)
  }

  public func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    try await grantAccessAsync(bundleIDs, toDeeplink: scheme)
  }

  public func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    try await revokeAccessAsync(bundleIDs, toDeeplink: scheme)
  }

  public func updateContacts(_ databaseDirectory: String) async throws {
    try await updateContactsAsync(databaseDirectory)
  }

  public func clearContacts() async throws {
    try await runSimulatorFrameworkBridgeAsync(withService: "contacts", action: "clear")
  }

  public func clearPhotos() async throws {
    try await runSimulatorFrameworkBridgeAsync(withService: "photos", action: "clear")
  }
}
