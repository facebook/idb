/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

public enum SimulatorPrivacyError: Error {
  case noDataDirectory
  case noDataDirectoryForPlists
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
  case tccDatabaseMissing(path: String)
  case tccDatabaseIsDirectory(path: String)
  case tccDatabaseNotWritable(path: String)
  case sqliteTaskFailed(exitCode: Int, stdOut: String, stdErr: String)
  case sqliteCommandFailed(stderr: String)
}

extension SimulatorPrivacyError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .noDataDirectory:
      return "Simulator has no data directory"
    case .noDataDirectoryForPlists:
      return "The Simulator has no data directory, so its plists cannot be located"
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

/// Grants and revokes an application's access to privacy-gated services and deeplink schemes.
public struct SimulatorPrivacyCommands {

  private let simulator: FBSimulator

  // MARK: - Initializers

  public static func commands(with simulator: FBSimulator) -> SimulatorPrivacyCommands {
    SimulatorPrivacyCommands(simulator: simulator)
  }

  internal init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Services

  public func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    if services.isEmpty {
      throw SimulatorPrivacyError.noServicesToGrant(bundleIDs: bundleIDs)
    }
    if bundleIDs.isEmpty {
      throw SimulatorPrivacyError.noBundleIDsToGrant(services: services)
    }

    var toApprove = services
    let coreSimulatorSettingMapping = Self.coreSimulatorSettingMapping(forOSVersion: simulator.osVersion)

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
    if !toApprove.isEmpty && !toApprove.isDisjoint(with: Set(Self.tccDatabaseMapping.keys)) {
      let tccServices = toApprove.intersection(Set(Self.tccDatabaseMapping.keys))
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
      throw SimulatorPrivacyError.unhandledGrantServices(services: toApprove)
    }
  }

  public func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    if services.isEmpty {
      throw SimulatorPrivacyError.noServicesToRevoke(bundleIDs: bundleIDs)
    }
    if bundleIDs.isEmpty {
      throw SimulatorPrivacyError.noBundleIDsToRevoke(services: services)
    }

    var toRevoke = services
    let coreSimulatorSettingMapping = Self.coreSimulatorSettingMapping(forOSVersion: simulator.osVersion)

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
    if !toRevoke.isEmpty && !toRevoke.isDisjoint(with: Set(Self.tccDatabaseMapping.keys)) {
      let tccServices = toRevoke.intersection(Set(Self.tccDatabaseMapping.keys))
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
      throw SimulatorPrivacyError.unhandledRevokeServices(services: toRevoke)
    }
  }

  // MARK: - Deeplinks

  public func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    if scheme.isEmpty {
      throw SimulatorPrivacyError.emptyScheme(operation: "url approve")
    }
    if bundleIDs.isEmpty {
      throw SimulatorPrivacyError.emptyBundleIDs(operation: "url approve")
    }

    let preferencesDirectory = (try requireDataDirectory() as NSString).appendingPathComponent("Library/Preferences")
    let schemeApprovalPlistPath = (preferencesDirectory as NSString).appendingPathComponent("com.apple.launchservices.schemeapproval.plist")

    var schemeApprovalProperties: NSMutableDictionary = NSMutableDictionary()
    if FileManager.default.fileExists(atPath: schemeApprovalPlistPath) {
      guard let dict = NSDictionary(contentsOfFile: schemeApprovalPlistPath)?.mutableCopy() as? NSMutableDictionary else {
        throw SimulatorPrivacyError.schemeApprovalPlistUnreadable(path: schemeApprovalPlistPath)
      }
      schemeApprovalProperties = dict
    }

    let urlKey = Self.magicDeeplinkKey(forScheme: scheme)
    for bundleID in bundleIDs {
      schemeApprovalProperties[urlKey] = bundleID
    }

    do {
      try FileManager.default.createDirectory(atPath: preferencesDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw SimulatorPrivacyError.schemeApprovalDirectoryCreationFailed(underlying: error)
    }
    if !schemeApprovalProperties.write(toFile: schemeApprovalPlistPath, atomically: true) {
      throw SimulatorPrivacyError.schemeApprovalPlistWriteFailed
    }
  }

  public func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    if scheme.isEmpty {
      throw SimulatorPrivacyError.emptyScheme(operation: "url revoke")
    }
    if bundleIDs.isEmpty {
      throw SimulatorPrivacyError.emptyBundleIDs(operation: "url revoke")
    }

    let preferencesDirectory = (try requireDataDirectory() as NSString).appendingPathComponent("Library/Preferences")
    let schemeApprovalPlistPath = (preferencesDirectory as NSString).appendingPathComponent("com.apple.launchservices.schemeapproval.plist")

    guard FileManager.default.fileExists(atPath: schemeApprovalPlistPath) else {
      return
    }
    guard let schemeApprovalProperties = NSDictionary(contentsOfFile: schemeApprovalPlistPath)?.mutableCopy() as? NSMutableDictionary else {
      throw SimulatorPrivacyError.schemeApprovalPlistUnreadable(path: schemeApprovalPlistPath)
    }

    let urlKey = Self.magicDeeplinkKey(forScheme: scheme)
    schemeApprovalProperties.removeObject(forKey: urlKey)

    if !schemeApprovalProperties.write(toFile: schemeApprovalPlistPath, atomically: true) {
      throw SimulatorPrivacyError.schemeApprovalPlistWriteFailed
    }
  }

  // MARK: - Private

  private func requireDataDirectory() throws -> String {
    guard let dataDirectory = simulator.dataDirectory else {
      throw SimulatorPrivacyError.noDataDirectoryForPlists
    }
    return dataDirectory
  }

  private func authorizeLocationSettings(_ bundleIDs: [String]) async throws {
    try await LocationServicesModificationStrategy(simulator: simulator)
      .approveLocationServices(forBundleIDs: bundleIDs)
  }

  private func revokeLocationSettings(_ bundleIDs: [String]) async throws {
    try await LocationServicesModificationStrategy(simulator: simulator)
      .revokeLocationServices(forBundleIDs: bundleIDs)
  }

  private func updateHealthService(_ bundleIDs: [String], approve approved: Bool) async throws {
    if bundleIDs.isEmpty {
      throw SimulatorPrivacyError.emptyBundleIDs(operation: "health approve")
    }
    let action = approved ? "approve" : "revoke"
    for bundleID in bundleIDs {
      try await simulator.runSimulatorFrameworkBridge(withService: "health", action: action, arguments: [bundleID])
    }
  }

  private func updateNotificationService(_ bundleIDs: [String], approve approved: Bool) async throws {
    if bundleIDs.isEmpty {
      throw SimulatorPrivacyError.emptyBundleIDs(operation: "notifications approve")
    }

    let action = approved ? "approve" : "revoke"
    for bundleID in bundleIDs {
      try await simulator.runSimulatorFrameworkBridge(withService: "notifications", action: action, arguments: [bundleID])
    }
  }

  private func coreSimulatorApprove(withBundleIDs bundleIDs: Set<String>, toServices services: Set<String>) throws {
    for bundleID in bundleIDs {
      for internalService in services {
        try simulator.device.setPrivacyAccessForService(internalService, bundleID: bundleID, granted: true)
      }
    }
  }

  private func coreSimulatorRevoke(withBundleIDs bundleIDs: Set<String>, toServices services: Set<String>) throws {
    for bundleID in bundleIDs {
      for internalService in services {
        try simulator.device.resetPrivacyAccess(forService: internalService, bundleID: bundleID)
      }
    }
  }

  // MARK: - TCC Database

  private func modifyTCCDatabase(withBundleIDs bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>, grantAccess: Bool) async throws {
    guard let dataDirectory = simulator.dataDirectory else {
      throw SimulatorPrivacyError.noDataDirectory
    }
    let databasePath = (dataDirectory as NSString).appendingPathComponent("Library/TCC/TCC.db")
    var isDirectory: ObjCBool = true
    if !FileManager.default.fileExists(atPath: databasePath, isDirectory: &isDirectory) {
      throw SimulatorPrivacyError.tccDatabaseMissing(path: databasePath)
    }
    if isDirectory.boolValue {
      throw SimulatorPrivacyError.tccDatabaseIsDirectory(path: databasePath)
    }
    if !FileManager.default.isWritableFile(atPath: databasePath) {
      throw SimulatorPrivacyError.tccDatabaseNotWritable(path: databasePath)
    }

    let logger = simulator.logger.withName("sqlite_auth")

    if grantAccess {
      try await grantAccessInTCCDatabase(databasePath, bundleIDs: bundleIDs, services: services, logger: logger)
    } else {
      try await revokeAccessInTCCDatabase(databasePath, bundleIDs: bundleIDs, services: services, logger: logger)
    }
  }

  private func grantAccessInTCCDatabase(_ databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, logger: (any FBControlCoreLogger)?) async throws {
    let query = try await Self.buildApprovalInsertQuery(forDatabase: databasePath, bundleIDs: bundleIDs, services: services, logger: logger)
    _ = try await Self.runSqliteCommand(onDatabase: databasePath, arguments: [query], logger: logger)
  }

  private func revokeAccessInTCCDatabase(_ databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, logger: (any FBControlCoreLogger)?) async throws {
    var deletions: [String] = []
    for bundleID in bundleIDs {
      for serviceName in Self.tccServiceNames(for: services) {
        deletions.append("(service = '\(serviceName)' AND client = '\(bundleID)')")
      }
    }
    if deletions.isEmpty {
      return
    }
    _ = try await Self.runSqliteCommand(
      onDatabase: databasePath,
      arguments: ["DELETE FROM access WHERE \(deletions.joined(separator: " OR "))"],
      logger: logger)
  }

  private static func buildApprovalInsertQuery(forDatabase databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, logger: (any FBControlCoreLogger)?) async throws -> String {
    let schema = try await runSqliteCommand(onDatabase: databasePath, arguments: [".schema access"], logger: logger)
    return approvalInsertQuery(forAccessSchema: schema, bundleIDs: bundleIDs, services: services)
  }

  private static func runSqliteCommand(onDatabase databasePath: String, arguments: [String], logger: (any FBControlCoreLogger)?) async throws -> String {
    let allArguments = [databasePath] + arguments
    logger?.log("Running sqlite3 \(FBCollectionInformation.oneLineDescription(from: allArguments))")
    let result = try await Subprocess(executable: "/usr/bin/sqlite3", arguments: allArguments)
      .run(exitPolicy: .mustExit([0, 1]), logger: logger)
    try result.checkExitedCleanly { code in
      SimulatorPrivacyError.sqliteTaskFailed(
        exitCode: Int(code),
        stdOut: result.standardOutput,
        stdErr: result.standardError)
    }
    if result.standardError.hasPrefix("Error") {
      throw SimulatorPrivacyError.sqliteCommandFailed(stderr: result.standardError)
    }
    return result.standardOutput
  }

  // MARK: - Service Mappings

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

  private static func coreSimulatorSettingMapping(forOSVersion osVersion: FBOSVersion) -> [FBTargetSettingsService: String] {
    osVersion.version.majorVersion >= 13 ? coreSimulatorSettingMappingPostIos13 : coreSimulatorSettingMappingPreIos13
  }

  internal static func filteredTCCApprovals(_ approvals: Set<FBTargetSettingsService>) -> Set<FBTargetSettingsService> {
    approvals.intersection(Set(tccDatabaseMapping.keys))
  }

  private static func tccServiceNames(for approvals: Set<FBTargetSettingsService>) -> [String] {
    filteredTCCApprovals(approvals).compactMap { tccDatabaseMapping[$0] }
  }

  internal static func magicDeeplinkKey(forScheme scheme: String) -> String {
    "com.apple.CoreSimulator.CoreSimulatorBridge-->\(scheme)"
  }

  // MARK: - Approval Rows

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
}
