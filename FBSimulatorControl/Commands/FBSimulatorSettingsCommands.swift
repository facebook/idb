/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// Dark/Light mode appearance.
/// Values match UIUserInterfaceStyle used by SimDevice's setUIInterfaceStyle:error:.
public enum FBSimulatorAppearance: Int, Sendable {
  case light = 1 // UIUserInterfaceStyleLight
  case dark = 2 // UIUserInterfaceStyleDark
}

/// Dynamic Type content size categories.
/// Values match the integer indices used by SimDevice's setContentSizeCategory:error:.
public enum FBSimulatorContentSizeCategory: Int, Sendable {
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

/// The ways settings operations can fail, as data rather than assembled strings.
public enum FBSimulatorSettingsError: Error {
  case noDataDirectory
  case noDataDirectoryForPlists
  case settingNotPreferenceBacked(setting: String)
  case noServicesToGrant(bundleIDs: Set<String>)
  case noBundleIDsToGrant(services: Set<FBTargetSettingsService>)
  case unhandledGrantServices(services: Set<FBTargetSettingsService>)
  case noServicesToRevoke(bundleIDs: Set<String>)
  case noBundleIDsToRevoke(services: Set<FBTargetSettingsService>)
  case unhandledRevokeServices(services: Set<FBTargetSettingsService>)
  case emptyScheme(operation: String)
  case emptyBundleIDs(operation: String)
  case schemeApprovalPlistUnreadable(path: String)
  case schemeApprovalDirectoryCreationFailed(underlying: Error)
  case schemeApprovalPlistWriteFailed
  case addressBookDirectoryMissing(path: String)
  case contactsDirectoryEnumerationFailed(path: String)
  case noContactsDatabases
  case noDnsServers
  case frameworkBridgeBinaryMissing
  case frameworkBridgeFailed(service: String, action: String, exitCode: Int32, stderr: String)
  case tccDatabaseMissing(path: String)
  case tccDatabaseIsDirectory(path: String)
  case tccDatabaseNotWritable(path: String)
  case sqliteTaskFailed(exitCode: Int, stdOut: String, stdErr: String)
  case sqliteCommandFailed(stderr: String)
}

extension FBSimulatorSettingsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .noDataDirectory:
      return "Simulator has no data directory"
    case .noDataDirectoryForPlists:
      return "The Simulator has no data directory, so its plists cannot be located"
    case let .settingNotPreferenceBacked(setting):
      return "Setting '\(setting)' is not backed by a preference"
    case let .noServicesToGrant(bundleIDs):
      return "Cannot approve any services for \(bundleIDs) since no services were provided"
    case let .noBundleIDsToGrant(services):
      return "Cannot approve \(services) since no bundle ids were provided"
    case let .unhandledGrantServices(services):
      return "Cannot approve \(FBCollectionInformation.oneLineDescription(from: Array(services))) since there is no handling of it"
    case let .noServicesToRevoke(bundleIDs):
      return "Cannot revoke any services for \(bundleIDs) since no services were provided"
    case let .noBundleIDsToRevoke(services):
      return "Cannot revoke \(services) since no bundle ids were provided"
    case let .unhandledRevokeServices(services):
      return "Cannot revoke \(FBCollectionInformation.oneLineDescription(from: Array(services))) since there is no handling of it"
    case let .emptyScheme(operation):
      return "Empty scheme provided to \(operation)"
    case let .emptyBundleIDs(operation):
      return "Empty bundleID set provided to \(operation)"
    case let .schemeApprovalPlistUnreadable(path):
      return "Failed to read the file at \(path)"
    case .schemeApprovalDirectoryCreationFailed:
      return "Failed to create folders for scheme approval plist"
    case .schemeApprovalPlistWriteFailed:
      return "Failed to write scheme approval plist"
    case let .addressBookDirectoryMissing(path):
      return "Expected Address Book path to exist at \(path) but it was not there"
    case let .contactsDirectoryEnumerationFailed(path):
      return "Could not enumerate directory at \(path)"
    case .noContactsDatabases:
      return "Could not update Address Book DBs when no databases are provided"
    case .noDnsServers:
      return "At least one DNS server address is required"
    case .frameworkBridgeBinaryMissing:
      return "SimulatorFrameworkBridge binary not found in the companion Resources directory"
    case let .frameworkBridgeFailed(service, action, exitCode, stderr):
      return "SimulatorFrameworkBridge \(service) \(action) failed with exit code \(exitCode): \(stderr)"
    case let .tccDatabaseMissing(path):
      return "Expected file to exist at path \(path) but it was not there"
    case let .tccDatabaseIsDirectory(path):
      return "Expected file to exist at path \(path) but it is a directory"
    case let .tccDatabaseNotWritable(path):
      return "Database file at path \(path) is not writable"
    case let .sqliteTaskFailed(exitCode, stdOut, stdErr):
      return "Task did not exit 0: \(exitCode) \(stdOut) \(stdErr)"
    case let .sqliteCommandFailed(stderr):
      return "Failed to execute sqlite command: \(stderr)"
    }
  }
}

public struct FBSimulatorSettingsCommands {

  // MARK: - Properties

  private let simulator: FBSimulator

  // MARK: - Initializers

  public static func commands(with simulator: FBSimulator) -> FBSimulatorSettingsCommands {
    FBSimulatorSettingsCommands(simulator: simulator)
  }

  internal init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // The command's simulator reference is weak; resolve it or fail uniformly across the settings ops.
  private func requireSimulator() throws -> FBSimulator {
    return simulator
  }

  private func requireDataDirectory(of simulator: FBSimulator) throws -> String {
    guard let dataDirectory = simulator.dataDirectory else {
      throw FBSimulatorSettingsError.noDataDirectoryForPlists
    }
    return dataDirectory
  }

  // Single source of truth for the SettingsCommands.apply entry point: switch over the setting and
  // dispatch to the transport-specific implementation.
  fileprivate func apply(_ setting: FBSimulatorSetting) async throws {
    switch setting {
    case let .hardwareKeyboard(enabled):
      try await setHardwareKeyboardEnabled(enabled)
    case let .slowAnimations(enabled):
      try await setSlowAnimationsEnabled(enabled)
    case let .increaseContrast(enabled):
      try await setIncreaseContrastEnabled(enabled)
    case let .autoFillPasswords(enabled):
      try await setPreferenceBacked(.autoFillPasswords, value: enabled ? "true" : "false", type: "bool")
    case let .appearance(appearance):
      try await setAppearance(appearance)
    case let .contentSize(category):
      try await setContentSizeCategory(category)
    case let .locale(localeIdentifier):
      try await setPreferenceBacked(.locale, value: localeIdentifier, type: nil)
    }
  }

  fileprivate func applyResolution(_ resolution: FBSimulatorSettingResolution) async throws {
    switch resolution {
    case let .setting(setting):
      try await apply(setting)
    case let .preference(name, value, type, domain):
      try await setPreference(name, value: value, type: type, domain: domain)
    }
  }

  fileprivate func currentAppearance() async throws -> FBSimulatorAppearance {
    let simulator = try requireSimulator()
    let raw = simulator.device.currentUIInterfaceStyle()
    return FBSimulatorAppearance(rawValue: raw) ?? .light
  }

  fileprivate func setAppearance(_ appearance: FBSimulatorAppearance) async throws {
    let simulator = try requireSimulator()
    try simulator.device.setUIInterfaceStyle(appearance.rawValue)
  }

  fileprivate func currentContentSizeCategory() async throws -> FBSimulatorContentSizeCategory {
    let simulator = try requireSimulator()
    let raw = simulator.device.currentContentSizeCategory()
    return FBSimulatorContentSizeCategory(rawValue: raw) ?? .large
  }

  fileprivate func setContentSizeCategory(_ category: FBSimulatorContentSizeCategory) async throws {
    let simulator = try requireSimulator()
    try simulator.device.setContentSizeCategory(category.rawValue)
  }

  fileprivate func currentStatusBarOverrides() async throws -> FBStatusBarOverride {
    let simulator = try requireSimulator()
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
    var override = FBStatusBarOverride()
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

  fileprivate func overrideStatusBar(_ override: FBStatusBarOverride?) async throws {
    let simulator = try requireSimulator()
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

  // MARK: - Async

  fileprivate func setHardwareKeyboardEnabled(_ enabled: Bool) async throws {
    let simulator = try requireSimulator()
    try simulator.device.setHardwareKeyboardEnabled(enabled, keyboardType: 0)
  }

  fileprivate func setSlowAnimationsEnabled(_ enabled: Bool) async throws {
    try await setDarwinNotificationState(enabled, name: slowAnimationsNotification)
  }

  fileprivate func setIncreaseContrastEnabled(_ enabled: Bool) async throws {
    let simulator = try requireSimulator()
    try simulator.device.setIncreaseContrastEnabled(enabled)
  }

  // Write a preference-backed setting through its centralized (domain, key). The ASP-cover rationale
  // for autofill-passwords lives on FBSimulatorSettingKey.preferenceBacking.
  fileprivate func setPreferenceBacked(_ key: FBSimulatorSettingKey, value: String, type: String?) async throws {
    guard let backing = key.preferenceBacking else {
      throw FBSimulatorSettingsError.settingNotPreferenceBacked(setting: key.rawValue)
    }
    try await setPreference(backing.key, value: value, type: type, domain: backing.domain)
  }

  fileprivate func setDarwinNotificationState(_ enabled: Bool, name: String) async throws {
    let simulator = try requireSimulator()
    try simulator.device.darwinNotificationSetState(enabled ? 1 : 0, name: name)
    try simulator.device.postDarwinNotification(name)
  }

  fileprivate func setPreference(_ name: String, value: String, type: String?, domain: String?) async throws {
    let simulator = try requireSimulator()
    try await FBPreferenceModificationStrategy(simulator: simulator)
      .setPreference(name, value: value, type: type, domain: domain)
  }

  fileprivate func getCurrentPreference(_ name: String, domain: String?) async throws -> String {
    let simulator = try requireSimulator()
    return try await FBPreferenceModificationStrategy(simulator: simulator)
      .getCurrentPreference(name, domain: domain)
  }

  fileprivate func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    let simulator = try requireSimulator()
    if services.isEmpty {
      throw FBSimulatorSettingsError.noServicesToGrant(bundleIDs: bundleIDs)
    }
    if bundleIDs.isEmpty {
      throw FBSimulatorSettingsError.noBundleIDsToGrant(services: services)
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
      try await modifyTCCDatabase(withBundleIDs: bundleIDs, toServices: tccServices, grantAccess: true)
    }
    if !toApprove.isEmpty && toApprove.contains(FBTargetSettingsService.location) {
      try await authorizeLocationSettings(Array(bundleIDs))
      toApprove.remove(FBTargetSettingsService.location)
    }
    if !toApprove.isEmpty && toApprove.contains(.notification) {
      try await updateNotificationService(Array(bundleIDs), approve: true)
      toApprove.remove(.notification)
    }
    if !toApprove.isEmpty && toApprove.contains(.health) {
      try await updateHealthService(Array(bundleIDs), approve: true)
      toApprove.remove(.health)
    }

    if !toApprove.isEmpty {
      throw FBSimulatorSettingsError.unhandledGrantServices(services: toApprove)
    }
  }

  fileprivate func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    let simulator = try requireSimulator()
    if services.isEmpty {
      throw FBSimulatorSettingsError.noServicesToRevoke(bundleIDs: bundleIDs)
    }
    if bundleIDs.isEmpty {
      throw FBSimulatorSettingsError.noBundleIDsToRevoke(services: services)
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
      try await modifyTCCDatabase(withBundleIDs: bundleIDs, toServices: tccServices, grantAccess: false)
    }
    if !toRevoke.isEmpty && toRevoke.contains(FBTargetSettingsService.location) {
      try await revokeLocationSettings(Array(bundleIDs))
      toRevoke.remove(FBTargetSettingsService.location)
    }
    if !toRevoke.isEmpty && toRevoke.contains(.notification) {
      try await updateNotificationService(Array(bundleIDs), approve: false)
      toRevoke.remove(.notification)
    }
    if !toRevoke.isEmpty && toRevoke.contains(.health) {
      try await updateHealthService(Array(bundleIDs), approve: false)
      toRevoke.remove(.health)
    }

    if !toRevoke.isEmpty {
      throw FBSimulatorSettingsError.unhandledRevokeServices(services: toRevoke)
    }
  }

  fileprivate func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    let simulator = try requireSimulator()
    if scheme.isEmpty {
      throw FBSimulatorSettingsError.emptyScheme(operation: "url approve")
    }
    if bundleIDs.isEmpty {
      throw FBSimulatorSettingsError.emptyBundleIDs(operation: "url approve")
    }

    let preferencesDirectory = (try requireDataDirectory(of: simulator) as NSString).appendingPathComponent("Library/Preferences")
    let schemeApprovalPlistPath = (preferencesDirectory as NSString).appendingPathComponent("com.apple.launchservices.schemeapproval.plist")

    var schemeApprovalProperties: NSMutableDictionary = NSMutableDictionary()
    if FileManager.default.fileExists(atPath: schemeApprovalPlistPath) {
      guard let dict = NSDictionary(contentsOfFile: schemeApprovalPlistPath)?.mutableCopy() as? NSMutableDictionary else {
        throw FBSimulatorSettingsError.schemeApprovalPlistUnreadable(path: schemeApprovalPlistPath)
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
      throw FBSimulatorSettingsError.schemeApprovalDirectoryCreationFailed(underlying: error)
    }
    if !schemeApprovalProperties.write(toFile: schemeApprovalPlistPath, atomically: true) {
      throw FBSimulatorSettingsError.schemeApprovalPlistWriteFailed
    }
  }

  fileprivate func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    let simulator = try requireSimulator()
    if scheme.isEmpty {
      throw FBSimulatorSettingsError.emptyScheme(operation: "url revoke")
    }
    if bundleIDs.isEmpty {
      throw FBSimulatorSettingsError.emptyBundleIDs(operation: "url revoke")
    }

    let preferencesDirectory = (try requireDataDirectory(of: simulator) as NSString).appendingPathComponent("Library/Preferences")
    let schemeApprovalPlistPath = (preferencesDirectory as NSString).appendingPathComponent("com.apple.launchservices.schemeapproval.plist")

    guard FileManager.default.fileExists(atPath: schemeApprovalPlistPath) else {
      return
    }
    guard let schemeApprovalProperties = NSDictionary(contentsOfFile: schemeApprovalPlistPath)?.mutableCopy() as? NSMutableDictionary else {
      throw FBSimulatorSettingsError.schemeApprovalPlistUnreadable(path: schemeApprovalPlistPath)
    }

    let urlKey = FBSimulatorSettingsCommands.magicDeeplinkKey(forScheme: scheme)
    schemeApprovalProperties.removeObject(forKey: urlKey)

    if !schemeApprovalProperties.write(toFile: schemeApprovalPlistPath, atomically: true) {
      throw FBSimulatorSettingsError.schemeApprovalPlistWriteFailed
    }
  }

  fileprivate func updateContacts(_ databaseDirectory: String) async throws {
    let simulator = try requireSimulator()
    let destinationDirectory = (try requireDataDirectory(of: simulator) as NSString).appendingPathComponent("Library/AddressBook")
    if !FileManager.default.fileExists(atPath: destinationDirectory) {
      throw FBSimulatorSettingsError.addressBookDirectoryMissing(path: destinationDirectory)
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

  fileprivate func setProxy(host: String, port: UInt, type: String) async throws {
    try await runSimulatorFrameworkBridge(
      withService: "proxy",
      action: "set",
      arguments: [host, "\(port)", type.isEmpty ? "http" : type])
  }

  fileprivate func clearProxy() async throws {
    try await runSimulatorFrameworkBridge(withService: "proxy", action: "clear")
  }

  fileprivate func listProxy() async throws -> String {
    try await runSimulatorFrameworkBridge(withService: "proxy", action: "list")
  }

  fileprivate func setDnsServers(_ servers: [String]) async throws {
    if servers.isEmpty {
      throw FBSimulatorSettingsError.noDnsServers
    }
    try await runSimulatorFrameworkBridge(withService: "dns", action: "set", arguments: servers)
  }

  fileprivate func clearDns() async throws {
    try await runSimulatorFrameworkBridge(withService: "dns", action: "clear")
  }

  fileprivate func listDns() async throws -> String {
    try await runSimulatorFrameworkBridge(withService: "dns", action: "list")
  }

  fileprivate func setHealthAuthorization(_ approved: Bool, forBundleID bundleID: String, typeIdentifiers: [String]) async throws {
    let action = approved ? "approve" : "revoke"
    let args = [bundleID] + typeIdentifiers
    try await runSimulatorFrameworkBridge(withService: "health", action: action, arguments: args)
  }

  fileprivate func clearHealthAuthorization(forBundleID bundleID: String) async throws {
    try await runSimulatorFrameworkBridge(withService: "health", action: "clear", arguments: [bundleID])
  }

  fileprivate func listHealthAuthorization(forBundleID bundleID: String) async throws -> String {
    try await runSimulatorFrameworkBridge(withService: "health", action: "list", arguments: [bundleID])
  }

  // MARK: - Private

  @discardableResult
  fileprivate func runSimulatorFrameworkBridge(withService service: String, action: String, arguments: [String] = []) async throws -> String {
    let simulator = try requireSimulator()
    guard let helperPath = BundledResources.path(forItem: "SimulatorFrameworkBridge") else {
      throw FBSimulatorSettingsError.frameworkBridgeBinaryMissing
    }

    // Spawn the bridge helper inside the simulator via CoreSimulator (the same
    // path as every other in-simulator spawn) rather than shelling out to
    // `simctl spawn`. The helper runs in the booted launchd domain, identically
    // to what `simctl spawn` provided.
    let output = try await simulator.launchProcessConsumingOutput(
      launchPath: helperPath,
      arguments: [service, action] + arguments)
    guard output.exitCode == 0 else {
      let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
      throw FBSimulatorSettingsError.frameworkBridgeFailed(service: service, action: action, exitCode: output.exitCode, stderr: stderr)
    }
    simulator.logger.log("SimulatorFrameworkBridge \(service) \(action) completed successfully")
    return String(data: output.stdout, encoding: .utf8) ?? ""
  }

  fileprivate func authorizeLocationSettings(_ bundleIDs: [String]) async throws {
    let simulator = try requireSimulator()
    try await FBLocationServicesModificationStrategy(simulator: simulator)
      .approveLocationServices(forBundleIDs: bundleIDs)
  }

  fileprivate func revokeLocationSettings(_ bundleIDs: [String]) async throws {
    let simulator = try requireSimulator()
    try await FBLocationServicesModificationStrategy(simulator: simulator)
      .revokeLocationServices(forBundleIDs: bundleIDs)
  }

  fileprivate func updateHealthService(_ bundleIDs: [String], approve approved: Bool) async throws {
    if bundleIDs.isEmpty {
      throw FBSimulatorSettingsError.emptyBundleIDs(operation: "health approve")
    }
    let action = approved ? "approve" : "revoke"
    for bundleID in bundleIDs {
      try await runSimulatorFrameworkBridge(withService: "health", action: action, arguments: [bundleID])
    }
  }

  fileprivate func updateNotificationService(_ bundleIDs: [String], approve approved: Bool) async throws {
    if bundleIDs.isEmpty {
      throw FBSimulatorSettingsError.emptyBundleIDs(operation: "notifications approve")
    }

    let action = approved ? "approve" : "revoke"
    for bundleID in bundleIDs {
      try await runSimulatorFrameworkBridge(withService: "notifications", action: action, arguments: [bundleID])
    }
  }

  fileprivate func modifyTCCDatabase(withBundleIDs bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>, grantAccess: Bool) async throws {
    let simulator = try requireSimulator()
    guard let dataDirectory = simulator.dataDirectory else {
      throw FBSimulatorSettingsError.noDataDirectory
    }
    let databasePath = (dataDirectory as NSString).appendingPathComponent("Library/TCC/TCC.db")
    var isDirectory: ObjCBool = true
    if !FileManager.default.fileExists(atPath: databasePath, isDirectory: &isDirectory) {
      throw FBSimulatorSettingsError.tccDatabaseMissing(path: databasePath)
    }
    if isDirectory.boolValue {
      throw FBSimulatorSettingsError.tccDatabaseIsDirectory(path: databasePath)
    }
    if !FileManager.default.isWritableFile(atPath: databasePath) {
      throw FBSimulatorSettingsError.tccDatabaseNotWritable(path: databasePath)
    }

    let logger = simulator.logger.withName("sqlite_auth")
    let queue = simulator.asyncQueue

    if grantAccess {
      try await grantAccessInTCCDatabase(databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger)
    } else {
      try await revokeAccessInTCCDatabase(databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger)
    }
  }

  fileprivate func coreSimulatorApprove(withBundleIDs bundleIDs: Set<String>, toServices services: Set<String>) throws {
    let simulator = try requireSimulator()
    for bundleID in bundleIDs {
      for internalService in services {
        try simulator.device.setPrivacyAccessForService(internalService, bundleID: bundleID, granted: true)
      }
    }
  }

  fileprivate func coreSimulatorRevoke(withBundleIDs bundleIDs: Set<String>, toServices services: Set<String>) throws {
    let simulator = try requireSimulator()
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

  private static let postiOS17AccessColumns = [
    "service",
    "client",
    "client_type",
    "auth_value",
    "auth_reason",
    "auth_version",
    "csreq",
    "policy_id",
    "indirect_object_identifier_type",
    "indirect_object_identifier",
    "indirect_object_code_identity",
    "flags",
    "last_modified",
    "pid",
    "pid_version",
    "boot_uuid",
    "last_reminded",
  ].joined(separator: ", ")

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

  internal static func filteredTCCApprovals(_ approvals: Set<FBTargetSettingsService>) -> Set<FBTargetSettingsService> {
    approvals.intersection(Set(tccDatabaseMapping.keys))
  }

  /// The TCC database names of the approvals that have one, so the row builders below never have to
  /// repeat the lookup that `filteredTCCApprovals` has already made.
  private static func tccServiceNames(for approvals: Set<FBTargetSettingsService>) -> [String] {
    filteredTCCApprovals(approvals).compactMap { tccDatabaseMapping[$0] }
  }

  fileprivate func grantAccessInTCCDatabase(_ databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) async throws {
    let query = try await FBSimulatorSettingsCommands.buildApprovalInsertQuery(forDatabase: databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger)
    _ = try await FBSimulatorSettingsCommands.runSqliteCommand(onDatabase: databasePath, arguments: [query], queue: queue, logger: logger)
  }

  fileprivate func revokeAccessInTCCDatabase(_ databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) async throws {
    var deletions: [String] = []
    for bundleID in bundleIDs {
      for serviceName in FBSimulatorSettingsCommands.tccServiceNames(for: services) {
        deletions.append("(service = '\(serviceName)' AND client = '\(bundleID)')")
      }
    }
    if deletions.isEmpty {
      return
    }
    _ = try await FBSimulatorSettingsCommands.runSqliteCommand(
      onDatabase: databasePath,
      arguments: ["DELETE FROM access WHERE \(deletions.joined(separator: " OR "))"],
      queue: queue,
      logger: logger)
  }

  fileprivate static func buildApprovalInsertQuery(forDatabase databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) async throws -> String {
    let schema = try await runSqliteCommand(onDatabase: databasePath, arguments: [".schema access"], queue: queue, logger: logger)
    return approvalInsertQuery(forAccessSchema: schema, bundleIDs: bundleIDs, services: services)
  }

  internal static func approvalInsertQuery(forAccessSchema schema: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    if schema.contains("last_reminded") {
      let rows = postiOS17ApprovalRows(forBundleIDs: bundleIDs, services: services)
      return "INSERT or REPLACE INTO access (\(postiOS17AccessColumns)) VALUES \(rows)"
    }

    let rows: String
    if schema.contains("auth_value") {
      rows = postiOS15ApprovalRows(forBundleIDs: bundleIDs, services: services)
    } else if schema.contains("last_modified") {
      rows = postiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    } else {
      rows = preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    }
    return "INSERT or REPLACE INTO access VALUES \(rows)"
  }

  internal static func preiOS12ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for serviceName in tccServiceNames(for: services) {
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 1, 0, 0, 0)")
      }
    }
    return tuples.joined(separator: ", ")
  }

  internal static func postiOS12ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    let timestamp = UInt(Date().timeIntervalSince1970)
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for serviceName in tccServiceNames(for: services) {
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 1, 1, NULL, NULL, NULL, 'UNUSED', NULL, NULL, \(timestamp))")
      }
    }
    return tuples.joined(separator: ", ")
  }

  internal static func postiOS15ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    let timestamp = UInt(Date().timeIntervalSince1970)
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for serviceName in tccServiceNames(for: services) {
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 2, 2, 2, NULL, NULL, NULL, 'UNUSED', NULL, NULL, \(timestamp))")
      }
    }
    return tuples.joined(separator: ", ")
  }

  internal static func postiOS17ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    let timestamp = UInt(Date().timeIntervalSince1970)
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for serviceName in tccServiceNames(for: services) {
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 2, 2, 2, NULL, NULL, NULL, 'UNUSED', NULL, NULL, \(timestamp), NULL, NULL, 'UNUSED', \(timestamp))")
      }
    }
    return tuples.joined(separator: ", ")
  }

  fileprivate static func runSqliteCommand(onDatabase databasePath: String, arguments: [String], queue: DispatchQueue, logger: (any FBControlCoreLogger)?) async throws -> String {
    let allArguments = [databasePath] + arguments
    logger?.log("Running sqlite3 \(FBCollectionInformation.oneLineDescription(from: allArguments))")
    let runFuture = FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/usr/bin/sqlite3", arguments: allArguments)
      .withStdOutInMemoryAsString()
      .withStdErrInMemoryAsString()
      .withTaskLifecycleLogging(to: logger)
      .runUntilCompletion(withAcceptableExitCodes: [0, 1])
    let task = try await bridgeFBFuture(runFuture)
    if task.exitCode.result != 0 as NSNumber {
      throw FBSimulatorSettingsError.sqliteTaskFailed(
        exitCode: task.exitCode.result?.intValue ?? 0,
        stdOut: (task.stdOut as? String) ?? "",
        stdErr: (task.stdErr as? String) ?? "")
    }
    if let stdErr = task.stdErr as? String, stdErr.hasPrefix("Error") {
      throw FBSimulatorSettingsError.sqliteCommandFailed(stderr: stdErr)
    }
    return (task.stdOut as String?) ?? ""
  }

  private static func contactsDatabaseFilePaths(fromContainingDirectory databaseDirectory: String) throws -> [String] {
    var filePaths: [String] = []
    guard let enumerator = FileManager.default.enumerator(atPath: databaseDirectory) else {
      throw FBSimulatorSettingsError.contactsDirectoryEnumerationFailed(path: databaseDirectory)
    }

    for case let path as String in enumerator {
      if !permissibleAddressBookDBFilenames.contains((path as NSString).lastPathComponent) {
        continue
      }
      let fullPath = (databaseDirectory as NSString).appendingPathComponent(path)
      filePaths.append(fullPath)
    }

    if filePaths.isEmpty {
      throw FBSimulatorSettingsError.noContactsDatabases
    }

    return filePaths
  }

  internal static func magicDeeplinkKey(forScheme scheme: String) -> String {
    "com.apple.CoreSimulator.CoreSimulatorBridge-->\(scheme)"
  }
}

// MARK: - FBSimulator+SettingsCommands

extension FBSimulator: SettingsCommands {

  public func apply(_ setting: FBSimulatorSetting) async throws {
    try await settings.apply(setting)
  }

  public func apply(_ resolution: FBSimulatorSettingResolution) async throws {
    try await settings.applyResolution(resolution)
  }

  /// Read the current value of a curated setting by name, mirroring `apply`'s name space and
  /// falling back to a raw preference read for any other name. Shared by idb and sime2e `get`.
  public func currentSettingValue(name: String, domain: String?) async throws -> String {
    guard let key = FBSimulatorSettingKey(rawValue: name) else {
      return try await getCurrentPreference(name, domain: domain)
    }
    switch key {
    case .autoFillPasswords, .locale:
      guard let backing = key.preferenceBacking else {
        return try await getCurrentPreference(name, domain: domain)
      }
      return try await getCurrentPreference(backing.key, domain: backing.domain)
    case .appearance:
      return (try await currentAppearance()).argumentName ?? "light"
    case .contentSize:
      return (try await currentContentSizeCategory()).argumentName ?? "large"
    case .hardwareKeyboard, .slowAnimations, .increaseContrast:
      // Set-only (SimDevice API / Darwin notification with no getter); no readable current value.
      return try await getCurrentPreference(name, domain: domain)
    }
  }

  public func getCurrentPreference(_ name: String, domain: String?) async throws -> String {
    try await settings.getCurrentPreference(name, domain: domain)
  }

  public func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    try await settings.grantAccess(bundleIDs, toServices: services)
  }

  public func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    try await settings.revokeAccess(bundleIDs, toServices: services)
  }

  public func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    try await settings.grantAccess(bundleIDs, toDeeplink: scheme)
  }

  public func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    try await settings.revokeAccess(bundleIDs, toDeeplink: scheme)
  }

  public func updateContacts(_ databaseDirectory: String) async throws {
    try await settings.updateContacts(databaseDirectory)
  }

  public func clearContacts() async throws {
    try await settings.runSimulatorFrameworkBridge(withService: "contacts", action: "clear")
  }

  public func clearPhotos() async throws {
    try await settings.runSimulatorFrameworkBridge(withService: "photos", action: "clear")
  }

  private func currentAppearance() async throws -> FBSimulatorAppearance {
    try await settings.currentAppearance()
  }

  private func currentContentSizeCategory() async throws -> FBSimulatorContentSizeCategory {
    try await settings.currentContentSizeCategory()
  }

  public func currentStatusBarOverrides() async throws -> FBStatusBarOverride {
    try await settings.currentStatusBarOverrides()
  }

  public func overrideStatusBar(_ override: FBStatusBarOverride?) async throws {
    try await settings.overrideStatusBar(override)
  }

  public func setProxy(host: String, port: UInt, type: String) async throws {
    try await settings.setProxy(host: host, port: port, type: type)
  }

  public func clearProxy() async throws {
    try await settings.clearProxy()
  }

  public func listProxy() async throws -> String {
    try await settings.listProxy()
  }

  public func setDnsServers(_ servers: [String]) async throws {
    try await settings.setDnsServers(servers)
  }

  public func clearDns() async throws {
    try await settings.clearDns()
  }

  public func listDns() async throws -> String {
    try await settings.listDns()
  }

  public func setHealthAuthorization(_ approved: Bool, forBundleID bundleID: String, typeIdentifiers: [String]) async throws {
    try await settings.setHealthAuthorization(approved, forBundleID: bundleID, typeIdentifiers: typeIdentifiers)
  }

  public func clearHealthAuthorization(forBundleID bundleID: String) async throws {
    try await settings.clearHealthAuthorization(forBundleID: bundleID)
  }

  public func listHealthAuthorization(forBundleID bundleID: String) async throws -> String {
    try await settings.listHealthAuthorization(forBundleID: bundleID)
  }
}
