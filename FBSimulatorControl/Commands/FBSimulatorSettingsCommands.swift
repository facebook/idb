// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// Helper to call [FBFuture futureWithFutures:] which is NS_SWIFT_UNAVAILABLE.
private func combineFutures(_ futures: [FBFuture<AnyObject>]) -> FBFuture<AnyObject> {
  let sel = NSSelectorFromString("futureWithFutures:")
  let method = FBFuture<AnyObject>.method(for: sel)
  typealias Signature = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
  let impl = unsafeBitCast(method, to: Signature.self)
  return impl(FBFuture<AnyObject>.self, sel, futures as NSArray)
}

private let springBoardServiceName = "com.apple.SpringBoard"

@objc(FBSimulatorSettingsCommands)
public final class FBSimulatorSettingsCommands: NSObject, FBSimulatorSettingsCommandsProtocol {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorSettingsCommands {
    return FBSimulatorSettingsCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Public

  @objc
  public func setHardwareKeyboardEnabled(_ enabled: Bool) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    if simulator.device.responds(to: NSSelectorFromString("setHardwareKeyboardEnabled:keyboardType:error:")) {
      return FBFuture.onQueue(
        simulator.workQueue,
        resolveValue: { (error: NSErrorPointer) -> NSNull? in
          do {
            try simulator.device.setHardwareKeyboardEnabled(enabled, keyboardType: 0)
            return NSNull()
          } catch let e as NSError {
            error?.pointee = e
            return nil
          }
        })
    }

    return
      (unsafeBitCast(simulator.connectToBridge(), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        fmap: { (bridgeObj: Any) -> FBFuture<AnyObject> in
          let bridge = bridgeObj as! FBSimulatorBridge
          return unsafeBitCast(bridge.setHardwareKeyboardEnabled(enabled), to: FBFuture<AnyObject>.self)
        })) as! FBFuture<NSNull>
  }

  @objc
  public func setPreference(_ name: String, value: String, type: String?, domain: String?) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return FBPreferenceModificationStrategy(simulator: simulator)
      .setPreference(name, value: value, type: type, domain: domain)
  }

  @objc
  public func getCurrentPreference(_ name: String, domain: String?) -> FBFuture<NSString> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSString>
    }
    return FBPreferenceModificationStrategy(simulator: simulator)
      .getCurrentPreference(name, domain: domain)
  }

  @objc
  public func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    if services.isEmpty {
      return FBSimulatorError.describe("Cannot approve any services for \(bundleIDs) since no services were provided")
        .failFuture() as! FBFuture<NSNull>
    }
    if bundleIDs.isEmpty {
      return FBSimulatorError.describe("Cannot approve \(services) since no bundle ids were provided")
        .failFuture() as! FBFuture<NSNull>
    }

    var futures: [FBFuture<NSNull>] = []
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
        futures.append(coreSimulatorApprove(withBundleIDs: bundleIDs, toServices: internalServices))
      }
    }
    if !toApprove.isEmpty && !toApprove.isDisjoint(with: Set(FBSimulatorSettingsCommands.tccDatabaseMapping.keys)) {
      let tccServices = toApprove.intersection(Set(FBSimulatorSettingsCommands.tccDatabaseMapping.keys))
      toApprove.subtract(tccServices)
      futures.append(modifyTCCDatabase(withBundleIDs: bundleIDs, toServices: tccServices, grantAccess: true))
    }
    if !toApprove.isEmpty && toApprove.contains(FBTargetSettingsService.location) {
      futures.append(authorizeLocationSettings(Array(bundleIDs)))
      toApprove.remove(FBTargetSettingsService.location)
    }
    if !toApprove.isEmpty && toApprove.contains(FBTargetSettingsService(rawValue: "notification")) {
      futures.append(updateNotificationService(Array(bundleIDs), approve: true))
      toApprove.remove(FBTargetSettingsService(rawValue: "notification"))
    }

    if !toApprove.isEmpty {
      return FBSimulatorError.describe("Cannot approve \(FBCollectionInformation.oneLineDescription(from: Array(toApprove))) since there is no handling of it")
        .failFuture() as! FBFuture<NSNull>
    }
    if futures.isEmpty {
      return FBFuture<NSNull>.empty()
    }
    if futures.count == 1 {
      return futures.first!
    }
    let castedFutures = futures.map { unsafeBitCast($0, to: FBFuture<AnyObject>.self) }
    return combineFutures(castedFutures).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  @objc
  public func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    if services.isEmpty {
      return FBSimulatorError.describe("Cannot revoke any services for \(bundleIDs) since no services were provided")
        .failFuture() as! FBFuture<NSNull>
    }
    if bundleIDs.isEmpty {
      return FBSimulatorError.describe("Cannot revoke \(services) since no bundle ids were provided")
        .failFuture() as! FBFuture<NSNull>
    }

    var futures: [FBFuture<NSNull>] = []
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
        futures.append(coreSimulatorRevoke(withBundleIDs: bundleIDs, toServices: internalServices))
      }
    }
    if !toRevoke.isEmpty && !toRevoke.isDisjoint(with: Set(FBSimulatorSettingsCommands.tccDatabaseMapping.keys)) {
      let tccServices = toRevoke.intersection(Set(FBSimulatorSettingsCommands.tccDatabaseMapping.keys))
      toRevoke.subtract(tccServices)
      futures.append(modifyTCCDatabase(withBundleIDs: bundleIDs, toServices: tccServices, grantAccess: false))
    }
    if !toRevoke.isEmpty && toRevoke.contains(FBTargetSettingsService.location) {
      futures.append(revokeLocationSettings(Array(bundleIDs)))
      toRevoke.remove(FBTargetSettingsService.location)
    }
    if !toRevoke.isEmpty && toRevoke.contains(FBTargetSettingsService(rawValue: "notification")) {
      futures.append(updateNotificationService(Array(bundleIDs), approve: false))
      toRevoke.remove(FBTargetSettingsService(rawValue: "notification"))
    }

    if !toRevoke.isEmpty {
      return FBSimulatorError.describe("Cannot revoke \(FBCollectionInformation.oneLineDescription(from: Array(toRevoke))) since there is no handling of it")
        .failFuture() as! FBFuture<NSNull>
    }
    if futures.isEmpty {
      return FBFuture<NSNull>.empty()
    }
    if futures.count == 1 {
      return futures.first!
    }
    let castedFutures = futures.map { unsafeBitCast($0, to: FBFuture<AnyObject>.self) }
    return combineFutures(castedFutures).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  @objc
  public func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    if scheme.isEmpty {
      return FBSimulatorError.describe("Empty scheme provided to url approve")
        .failFuture() as! FBFuture<NSNull>
    }
    if bundleIDs.isEmpty {
      return FBSimulatorError.describe("Empty bundleID set provided to url approve")
        .failFuture() as! FBFuture<NSNull>
    }

    let preferencesDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Library/Preferences")
    let schemeApprovalPlistPath = (preferencesDirectory as NSString).appendingPathComponent("com.apple.launchservices.schemeapproval.plist")

    var schemeApprovalProperties: NSMutableDictionary = NSMutableDictionary()
    if FileManager.default.fileExists(atPath: schemeApprovalPlistPath) {
      guard let dict = NSDictionary(contentsOfFile: schemeApprovalPlistPath)?.mutableCopy() as? NSMutableDictionary else {
        return FBSimulatorError.describe("Failed to read the file at \(schemeApprovalPlistPath)")
          .failFuture() as! FBFuture<NSNull>
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
      return FBSimulatorError.describe("Failed to create folders for scheme approval plist")
        .failFuture() as! FBFuture<NSNull>
    }
    if !schemeApprovalProperties.write(toFile: schemeApprovalPlistPath, atomically: true) {
      return FBSimulatorError.describe("Failed to write scheme approval plist")
        .failFuture() as! FBFuture<NSNull>
    }
    return FBFuture<NSNull>.empty()
  }

  @objc
  public func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    if scheme.isEmpty {
      return FBSimulatorError.describe("Empty scheme provided to url revoke")
        .failFuture() as! FBFuture<NSNull>
    }
    if bundleIDs.isEmpty {
      return FBSimulatorError.describe("Empty bundleID set provided to url revoke")
        .failFuture() as! FBFuture<NSNull>
    }

    let preferencesDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Library/Preferences")
    let schemeApprovalPlistPath = (preferencesDirectory as NSString).appendingPathComponent("com.apple.launchservices.schemeapproval.plist")

    guard FileManager.default.fileExists(atPath: schemeApprovalPlistPath) else {
      return FBFuture<NSNull>.empty()
    }
    guard let schemeApprovalProperties = NSDictionary(contentsOfFile: schemeApprovalPlistPath)?.mutableCopy() as? NSMutableDictionary else {
      return FBSimulatorError.describe("Failed to read the file at \(schemeApprovalPlistPath)")
        .failFuture() as! FBFuture<NSNull>
    }

    let urlKey = FBSimulatorSettingsCommands.magicDeeplinkKey(forScheme: scheme)
    schemeApprovalProperties.removeObject(forKey: urlKey)

    if !schemeApprovalProperties.write(toFile: schemeApprovalPlistPath, atomically: true) {
      return FBSimulatorError.describe("Failed to write scheme approval plist")
        .failFuture() as! FBFuture<NSNull>
    }
    return FBFuture<NSNull>.empty()
  }

  @objc
  public func updateContacts(_ databaseDirectory: String) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    let destinationDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Library/AddressBook")
    if !FileManager.default.fileExists(atPath: destinationDirectory) {
      return FBSimulatorError.describe("Expected Address Book path to exist at \(destinationDirectory) but it was not there")
        .failFuture() as! FBFuture<NSNull>
    }

    let sourceFilePaths: [String]
    do {
      sourceFilePaths = try FBSimulatorSettingsCommands.contactsDatabaseFilePaths(fromContainingDirectory: databaseDirectory)
    } catch {
      return FBFuture(error: error)
    }

    for sourceFilePath in sourceFilePaths {
      let destinationFilePath = (destinationDirectory as NSString).appendingPathComponent((sourceFilePath as NSString).lastPathComponent)
      do {
        if FileManager.default.fileExists(atPath: destinationFilePath) {
          try FileManager.default.removeItem(atPath: destinationFilePath)
        }
        try FileManager.default.copyItem(atPath: sourceFilePath, toPath: destinationFilePath)
      } catch {
        return FBFuture(error: error)
      }
    }

    return FBFuture<NSNull>.empty()
  }

  @objc
  public func clearContacts() -> FBFuture<NSNull> {
    return runSimulatorFrameworkBridge(withService: "contacts", action: "clear")
  }

  @objc
  public func clearPhotos() -> FBFuture<NSNull> {
    return runSimulatorFrameworkBridge(withService: "photos", action: "clear")
  }

  // MARK: - Private

  private func runSimulatorFrameworkBridge(withService service: String, action: String) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    guard let helperPath = Bundle(for: FBSimulatorSettingsCommands.self).path(forResource: "SimulatorFrameworkBridge", ofType: nil) else {
      return FBSimulatorError.describe("SimulatorFrameworkBridge binary not found in bundle resources. Ensure FBSimulatorControl was built correctly.")
        .failFuture() as! FBFuture<NSNull>
    }
    if !FileManager.default.fileExists(atPath: helperPath) {
      return FBSimulatorError.describe("SimulatorFrameworkBridge binary found in bundle but does not exist at path: \(helperPath)")
        .failFuture() as! FBFuture<NSNull>
    }
    return
      (unsafeBitCast(
        simulator.simctlExecutor.taskBuilder(withCommand: "spawn", arguments: [helperPath, service, action])
          .runUntilCompletion(withAcceptableExitCodes: [0]),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        simulator.asyncQueue,
        fmap: { (_: Any) -> FBFuture<AnyObject> in
          simulator.logger?.log("SimulatorFrameworkBridge \(service) \(action) completed successfully")
          return FBFuture(result: NSNull())
        })) as! FBFuture<NSNull>
  }

  private func authorizeLocationSettings(_ bundleIDs: [String]) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return FBLocationServicesModificationStrategy(simulator: simulator)
      .approveLocationServices(forBundleIDs: bundleIDs)
  }

  private func revokeLocationSettings(_ bundleIDs: [String]) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return FBLocationServicesModificationStrategy(simulator: simulator)
      .revokeLocationServices(forBundleIDs: bundleIDs)
  }

  private func updateNotificationService(_ bundleIDs: [String], approve approved: Bool) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    if bundleIDs.isEmpty {
      return FBSimulatorError.describe("Empty bundleID set provided to notifications approve")
        .failFuture() as! FBFuture<NSNull>
    }

    let bulletinDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Library/BulletinBoard")
    let notificationsApprovalPlistPath = (bulletinDirectory as NSString).appendingPathComponent("VersionedSectionInfo.plist")

    guard let sectionInfo = NSMutableDictionary(contentsOfFile: notificationsApprovalPlistPath) else {
      return FBSimulatorError.describe("Failed to load sectionInfo")
        .failFuture() as! FBFuture<NSNull>
    }

    let sectionInfoDict = sectionInfo["sectionInfo"] as? NSMutableDictionary

    for bundleID in bundleIDs {
      var data: Data? = sectionInfoDict?.object(forKey: bundleID) as? Data
      if data == nil {
        data = sectionInfoDict?.allValues.first as? Data
      }
      guard let data else {
        return FBSimulatorError.describe("No section info for \(bundleID)")
          .failFuture() as! FBFuture<NSNull>
      }
      if approved {
        guard let properties = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? NSDictionary else {
          return FBSimulatorError.describe("Failed to deserialize section info plist")
            .failFuture() as! FBFuture<NSNull>
        }
        if let objects = properties["$objects"] as? NSMutableArray {
          objects[2] = bundleID
          if let dict = objects[3] as? NSMutableDictionary {
            dict["allowsNotifications"] = true
          }
        }

        guard let resultData = try? PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0) else {
          return FBSimulatorError.describe("Failed to serialize section info plist")
            .failFuture() as! FBFuture<NSNull>
        }
        sectionInfoDict?[bundleID] = resultData
      } else {
        sectionInfoDict?.removeObject(forKey: bundleID)
      }
    }

    if !sectionInfo.write(toFile: notificationsApprovalPlistPath, atomically: true) {
      return FBSimulatorError.describe("Failed to write sectionInfo data to plist")
        .failFuture() as! FBFuture<NSNull>
    }

    if simulator.state == .booted {
      return (simulator.stopService(withName: springBoardServiceName) as FBFuture).mapReplace(NSNull()) as! FBFuture<NSNull>
    } else {
      return FBFuture<NSNull>.empty()
    }
  }

  private func modifyTCCDatabase(withBundleIDs bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>, grantAccess: Bool) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    guard let dataDirectory = simulator.dataDirectory else {
      return FBSimulatorError.describe("Simulator has no data directory").failFuture() as! FBFuture<NSNull>
    }
    let databasePath = (dataDirectory as NSString).appendingPathComponent("Library/TCC/TCC.db")
    var isDirectory: ObjCBool = true
    if !FileManager.default.fileExists(atPath: databasePath, isDirectory: &isDirectory) {
      return FBSimulatorError.describe("Expected file to exist at path \(databasePath) but it was not there")
        .failFuture() as! FBFuture<NSNull>
    }
    if isDirectory.boolValue {
      return FBSimulatorError.describe("Expected file to exist at path \(databasePath) but it is a directory")
        .failFuture() as! FBFuture<NSNull>
    }
    if !FileManager.default.isWritableFile(atPath: databasePath) {
      return FBSimulatorError.describe("Database file at path \(databasePath) is not writable")
        .failFuture() as! FBFuture<NSNull>
    }

    let logger = simulator.logger?.withName("sqlite_auth")
    let queue = simulator.asyncQueue

    if grantAccess {
      return grantAccessInTCCDatabase(databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger)
    } else {
      return revokeAccessInTCCDatabase(databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger)
    }
  }

  private func coreSimulatorApprove(withBundleIDs bundleIDs: Set<String>, toServices services: Set<String>) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    for bundleID in bundleIDs {
      for internalService in services {
        do {
          try simulator.device.setPrivacyAccessForService(internalService, bundleID: bundleID, granted: true)
        } catch {
          return FBFuture(error: error)
        }
      }
    }
    return FBFuture<NSNull>.empty()
  }

  private func coreSimulatorRevoke(withBundleIDs bundleIDs: Set<String>, toServices services: Set<String>) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    for bundleID in bundleIDs {
      for internalService in services {
        do {
          try simulator.device.resetPrivacyAccess(forService: internalService, bundleID: bundleID)
        } catch {
          return FBFuture(error: error)
        }
      }
    }
    return FBFuture<NSNull>.empty()
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

  private class func filteredTCCApprovals(_ approvals: Set<FBTargetSettingsService>) -> Set<FBTargetSettingsService> {
    return approvals.intersection(Set(tccDatabaseMapping.keys))
  }

  private func grantAccessInTCCDatabase(_ databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return
      (unsafeBitCast(
        FBSimulatorSettingsCommands.buildRows(forDatabase: databasePath, bundleIDs: bundleIDs, services: services, queue: queue, logger: logger),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        simulator.workQueue,
        fmap: { (rowsObj: Any) -> FBFuture<AnyObject> in
          let rows = rowsObj as! String
          return unsafeBitCast(
            FBSimulatorSettingsCommands.runSqliteCommand(onDatabase: databasePath, arguments: ["INSERT or REPLACE INTO access VALUES \(rows)"], queue: queue, logger: logger),
            to: FBFuture<AnyObject>.self)
        }
      )
      .mapReplace(NSNull())) as! FBFuture<NSNull>
  }

  private func revokeAccessInTCCDatabase(_ databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) -> FBFuture<NSNull> {
    var deletions: [String] = []
    for bundleID in bundleIDs {
      for service in FBSimulatorSettingsCommands.filteredTCCApprovals(services) {
        let serviceName = FBSimulatorSettingsCommands.tccDatabaseMapping[service]!
        deletions.append("(service = '\(serviceName)' AND client = '\(bundleID)')")
      }
    }
    if deletions.isEmpty {
      return FBFuture<NSNull>.empty()
    }
    return
      (FBSimulatorSettingsCommands.runSqliteCommand(
        onDatabase: databasePath,
        arguments: ["DELETE FROM access WHERE \(deletions.joined(separator: " OR "))"],
        queue: queue,
        logger: logger) as FBFuture)
      .mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  private class func buildRows(forDatabase databasePath: String, bundleIDs: Set<String>, services: Set<FBTargetSettingsService>, queue: DispatchQueue, logger: (any FBControlCoreLogger)?) -> FBFuture<NSString> {
    return
      (unsafeBitCast(
        runSqliteCommand(onDatabase: databasePath, arguments: [".schema access"], queue: queue, logger: logger),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        queue,
        map: { (resultObj: Any) -> NSString in
          let result = resultObj as! String
          if result.contains("last_reminded") {
            return postiOS17ApprovalRows(forBundleIDs: bundleIDs, services: services) as NSString
          } else if result.contains("auth_value") {
            return postiOS15ApprovalRows(forBundleIDs: bundleIDs, services: services) as NSString
          } else if result.contains("last_modified") {
            return postiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services) as NSString
          } else {
            return preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services) as NSString
          }
        })) as! FBFuture<NSString>
  }

  private class func preiOS12ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
    var tuples: [String] = []
    for bundleID in bundleIDs {
      for service in filteredTCCApprovals(services) {
        let serviceName = tccDatabaseMapping[service]!
        tuples.append("('\(serviceName)', '\(bundleID)', 0, 1, 0, 0, 0)")
      }
    }
    return tuples.joined(separator: ", ")
  }

  private class func postiOS12ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
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

  private class func postiOS15ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
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

  private class func postiOS17ApprovalRows(forBundleIDs bundleIDs: Set<String>, services: Set<FBTargetSettingsService>) -> String {
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

  private class func runSqliteCommand(onDatabase databasePath: String, arguments: [String], queue: DispatchQueue, logger: (any FBControlCoreLogger)?) -> FBFuture<NSString> {
    let allArguments = [databasePath] + arguments
    logger?.log("Running sqlite3 \(FBCollectionInformation.oneLineDescription(from: allArguments))")
    return
      (unsafeBitCast(
        FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/usr/bin/sqlite3", arguments: allArguments)
          .withStdOutInMemoryAsString()
          .withStdErrInMemoryAsString()
          .withTaskLifecycleLogging(to: logger)
          .runUntilCompletion(withAcceptableExitCodes: [0, 1]),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        queue,
        fmap: { (taskObj: Any) -> FBFuture<AnyObject> in
          let task = taskObj as! FBSubprocess<NSNull, NSString, NSString>
          if task.exitCode.result != 0 as NSNumber {
            return FBSimulatorError.describe("Task did not exit 0: \(task.exitCode.result ?? 0) \(task.stdOut ?? "") \(task.stdErr ?? "")")
              .failFuture()
          }
          if let stdErr = task.stdErr as? String, stdErr.hasPrefix("Error") {
            return FBSimulatorError.describe("Failed to execute sqlite command: \(stdErr)")
              .failFuture()
          }
          return FBFuture(result: task.stdOut ?? "" as NSString)
        })) as! FBFuture<NSString>
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

  private class func magicDeeplinkKey(forScheme scheme: String) -> String {
    return "com.apple.CoreSimulator.CoreSimulatorBridge-->\(scheme)"
  }
}
