/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@_implementationOnly import FBDeviceControl
@_implementationOnly import FBSimulatorControl
import Foundation
import XCTestBootstrap

// swiftlint:disable force_cast force_unwrapping

@objc public final class FBIDBCommandExecutor: NSObject {

  private let target: FBiOSTarget
  private let logger: FBIDBLogger
  private let debugserverPort: in_port_t

  @objc public let storageManager: FBIDBStorageManager
  @objc public var debugServer: FBDebugServer?
  @objc public let temporaryDirectory: FBTemporaryDirectory

  // MARK: - Initializers

  @objc public static func commandExecutor(forTarget target: FBiOSTarget, storageManager: FBIDBStorageManager, temporaryDirectory: FBTemporaryDirectory, debugserverPort: in_port_t, logger: FBIDBLogger) -> FBIDBCommandExecutor {
    return FBIDBCommandExecutor(target: target, storageManager: storageManager, temporaryDirectory: temporaryDirectory, debugserverPort: debugserverPort, logger: logger.withName("grpc_handler") as! FBIDBLogger)
  }

  private init(target: FBiOSTarget, storageManager: FBIDBStorageManager, temporaryDirectory: FBTemporaryDirectory, debugserverPort: in_port_t, logger: FBIDBLogger) {
    self.target = target
    self.storageManager = storageManager
    self.temporaryDirectory = temporaryDirectory
    self.debugserverPort = debugserverPort
    self.logger = logger
    super.init()
  }

  // MARK: - Installation

  @objc public func list_apps(_ fetchProcessState: Bool) -> FBFuture<NSDictionary> {
    return FBFuture<AnyObject>.combine([
      target.installedApplications() as! FBFuture<AnyObject>,
      fetchProcessState ? target.runningApplications() as! FBFuture<AnyObject> : FBFuture(result: NSDictionary()),
    ])
    .onQueue(
      target.workQueue,
      map: { results -> AnyObject in
        let tuple = results as [AnyObject]
        let installedApps = tuple[0] as! [FBInstalledApplication]
        let runningApps = tuple[1] as! [String: NSNumber]
        let listing = NSMutableDictionary()
        for application in installedApps {
          listing[application] = runningApps[application.bundle.identifier] ?? NSNull()
        }
        return listing
      }) as! FBFuture<NSDictionary>
  }

  @objc public func install_app_file_path(_ filePath: String, make_debuggable makeDebuggable: Bool, override_modification_time overrideModificationTime: Bool) -> FBFuture<FBInstalledArtifact> {
    if FBBundleDescriptor.isApplication(atPath: filePath) {
      guard let bundleDescriptor = try? FBBundleDescriptor.bundle(fromPath: filePath) else {
        return FBFuture(error: FBControlCoreError.describe("Failed to read bundle at \(filePath)").build() as NSError)
      }
      return installAppBundle(FBFutureContext(result: bundleDescriptor as AnyObject), makeDebuggable: makeDebuggable)
    } else {
      return installExtractedApp(temporaryDirectory.withArchiveExtracted(fromFile: filePath, overrideModificationTime: overrideModificationTime) as! FBFutureContext<AnyObject>, makeDebuggable: makeDebuggable)
    }
  }

  @objc public func install_app_stream(_ input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, make_debuggable makeDebuggable: Bool, override_modification_time overrideModificationTime: Bool) -> FBFuture<FBInstalledArtifact> {
    return installExtractedApp(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: compression, overrideModificationTime: overrideModificationTime) as! FBFutureContext<AnyObject>, makeDebuggable: makeDebuggable)
  }

  @objc public func install_xctest_app_file_path(_ filePath: String, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    return installXctestFilePath(FBFutureContext(future: FBFuture(result: URL(fileURLWithPath: filePath) as AnyObject)), skipSigningBundles: skipSigningBundles)
  }

  @objc public func install_xctest_app_stream(_ stream: FBProcessInput<AnyObject>, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    return installXctest(temporaryDirectory.withArchiveExtracted(fromStream: stream, compression: .GZIP) as! FBFutureContext<AnyObject>, skipSigningBundles: skipSigningBundles)
  }

  @objc public func install_dylib_file_path(_ filePath: String) -> FBFuture<FBInstalledArtifact> {
    return installFile(FBFutureContext(future: FBFuture(result: URL(fileURLWithPath: filePath) as AnyObject)), intoStorage: storageManager.dylib)
  }

  @objc public func install_dylib_stream(_ input: FBProcessInput<AnyObject>, name: String) -> FBFuture<FBInstalledArtifact> {
    return installFile(temporaryDirectory.withGzipExtracted(fromStream: input, name: name) as! FBFutureContext<AnyObject>, intoStorage: storageManager.dylib)
  }

  @objc public func install_framework_file_path(_ filePath: String) -> FBFuture<FBInstalledArtifact> {
    return installBundle(FBFutureContext(future: FBFuture(result: URL(fileURLWithPath: filePath) as AnyObject)), intoStorage: storageManager.framework)
  }

  @objc public func install_framework_stream(_ input: FBProcessInput<AnyObject>) -> FBFuture<FBInstalledArtifact> {
    return installBundle(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: .GZIP) as! FBFutureContext<AnyObject>, intoStorage: storageManager.framework)
  }

  @objc public func install_dsym_file_path(_ filePath: String, linkTo: FBDsymInstallLinkToBundle?) -> FBFuture<FBInstalledArtifact> {
    return installAndLinkDsym(FBFutureContext(future: FBFuture(result: URL(fileURLWithPath: filePath) as AnyObject)), intoStorage: storageManager.dsym, linkTo: linkTo)
  }

  @objc public func install_dsym_stream(_ input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, linkTo: FBDsymInstallLinkToBundle?) -> FBFuture<FBInstalledArtifact> {
    return installAndLinkDsym(dsymDirnameFromUnzipDir(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: compression) as! FBFutureContext<AnyObject>), intoStorage: storageManager.dsym, linkTo: linkTo)
  }

  // MARK: - Public Methods

  public func take_screenshot(_ format: FBScreenshotFormat) async throws -> Data {
    let commands = target as FBScreenshotCommands
    return try await bridgeFBFuture(commands.takeScreenshot(format)) as Data
  }

  public func accessibility_info_at_point(_ value: NSValue?, nestedFormat: Bool) async throws -> FBAccessibilityElementsResponse {
    guard let cmds = target as? FBAccessibilityCommands else {
      throw FBIDBError.describe("Target doesn't conform to FBAccessibilityCommands protocol \(target)").build()
    }
    let options = FBAccessibilityRequestOptions.`default`()
    options.nestedFormat = nestedFormat
    options.enableLogging = true

    let element: FBAccessibilityElement
    if let value {
      element = try await bridgeFBFuture(cmds.accessibilityElement(at: value.pointValue))
    } else {
      element = try await bridgeFBFuture(cmds.accessibilityElementForFrontmostApplication())
    }
    defer { element.close() }
    return try element.serialize(with: options)
  }

  public func add_media(_ filePaths: [URL]) async throws {
    let commands = try mediaCommands()
    try await bridgeFBFutureVoid(commands.addMedia(filePaths))
  }

  public func set_location(_ latitude: Double, longitude: Double) async throws {
    guard let commands = target as? AsyncLocationCommands else {
      throw FBIDBError.describe("\(target) does not conform to FBLocationCommands").build()
    }
    try await commands.overrideLocation(longitude: longitude, latitude: latitude)
  }

  public func clear_keychain() async throws {
    let commands = try keychainCommands()
    try await bridgeFBFutureVoid(commands.clearKeychain())
  }

  public func approve(_ services: Set<FBTargetSettingsService>, for_application bundleID: String) async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.grantAccess(Set([bundleID]), toServices: services))
  }

  public func revoke(_ services: Set<FBTargetSettingsService>, for_application bundleID: String) async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.revokeAccess(Set([bundleID]), toServices: services))
  }

  public func approve_deeplink(_ scheme: String, for_application bundleID: String) async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.grantAccess(Set([bundleID]), toDeeplink: scheme))
  }

  public func revoke_deeplink(_ scheme: String, for_application bundleID: String) async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.revokeAccess(Set([bundleID]), toDeeplink: scheme))
  }

  public func open_url(_ url: String) async throws {
    let commands = try lifecycleCommands()
    try await bridgeFBFutureVoid(commands.open(URL(string: url)!))
  }

  public func focus() async throws {
    let commands = try lifecycleCommands()
    try await bridgeFBFutureVoid(commands.focus())
  }

  public func update_contacts(_ dbTarData: Data) async throws {
    let commands = try settingsCommands()
    try await withFBFutureContext(temporaryDirectory.withArchiveExtracted(dbTarData)) { tempDir in
      try await bridgeFBFutureVoid(commands.updateContacts((tempDir as URL).path))
    }
  }

  public func clear_contacts() async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.clearContacts())
  }

  public func clear_photos() async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.clearPhotos())
  }

  public func list_test_bundles() async throws -> [FBXCTestDescriptor] {
    return try storageManager.xctest.listTestDescriptors()
  }

  private static let ListTestBundleTimeout: TimeInterval = 180.0

  public func list_tests_in_bundle(_ bundleID: String, with_app appPath: String?) async throws -> [String] {
    var resolvedAppPath = appPath
    if resolvedAppPath == "" {
      resolvedAppPath = nil
    }

    if let app = resolvedAppPath, storageManager.application.persistedBundleIDs.contains(app) {
      resolvedAppPath = storageManager.application.persistedBundles[app]?.path
    }

    let finalAppPath = resolvedAppPath
    let testDescriptor = try storageManager.xctest.testDescriptor(withID: bundleID)
    typealias ListTestsFn = @convention(c) (AnyObject, Selector, NSString, TimeInterval, NSString?) -> AnyObject
    let sel = NSSelectorFromString("listTestsForBundleAtPath:timeout:withAppAtPath:")
    let imp = unsafeBitCast((target as AnyObject).method(for: sel), to: ListTestsFn.self)
    let future = imp(target as AnyObject, sel, testDescriptor.url.path as NSString, FBIDBCommandExecutor.ListTestBundleTimeout, finalAppPath as NSString?) as! FBFuture<NSArray>
    return try await bridgeFBFutureArray(future)
  }

  public func uninstall_application(_ bundleID: String) async throws {
    try await bridgeFBFutureVoid(target.uninstallApplication(withBundleID: bundleID))
  }

  public func kill_application(_ bundleID: String) async throws {
    _ = try await bridgeFBFuture(target.killApplication(withBundleID: bundleID).fallback(NSNull()))
  }

  public func launch_app(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    var replacements: [String: String] = [:]
    replacements.merge(storageManager.replacementMapping) { _, new in new }
    replacements.merge(target.replacementMapping()) { _, new in new }
    let environment = applyEnvironmentReplacements(configuration.environment, replacements: replacements)

    let derived = FBApplicationLaunchConfiguration(
      bundleID: configuration.bundleID,
      bundleName: configuration.bundleName,
      arguments: configuration.arguments,
      environment: environment,
      waitForDebugger: configuration.waitForDebugger,
      io: configuration.io,
      launchMode: configuration.launchMode
    )
    return try await bridgeFBFuture(target.launchApplication(derived))
  }

  public func crash_list(_ predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    return try await bridgeFBFutureArray(target.crashes(predicate, useCache: false))
  }

  public func crash_show(_ predicate: NSPredicate) async throws -> FBCrashLog {
    let crashArray: [FBCrashLogInfo] = try await bridgeFBFutureArray(target.crashes(predicate, useCache: true))
    if crashArray.count > 1 {
      throw FBIDBError.describe("More than one crash log matching \(predicate)").build()
    }
    guard let first = crashArray.first else {
      throw FBIDBError.describe("No crashes matching \(predicate)").build()
    }
    return try first.obtainCrashLog()
  }

  public func crash_delete(_ predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    return try await bridgeFBFutureArray(target.pruneCrashes(predicate))
  }

  @objc public func xctest_run(_ request: FBXCTestRunRequest, reporter: FBXCTestReporter, logger: FBControlCoreLogger) -> FBFuture<FBIDBTestOperation> {
    return request.start(withBundleStorageManager: storageManager.xctest, target: target, reporter: reporter, logger: logger, temporaryDirectory: temporaryDirectory)
  }

  @objc public func debugserver_start(_ bundleID: String) -> FBFuture<AnyObject> {
    guard let commands = target as? FBDebuggerCommands else {
      return FBControlCoreError.describe("Target doesn't conform to FBDebuggerCommands protocol \(target)").failFuture()
    }

    return debugserver_prepare(bundleID)
      .onQueue(
        target.workQueue,
        fmap: { application in
          let app = application as! FBBundleDescriptor
          return commands.launchDebugServer(forHostApplication: app, port: self.debugserverPort) as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        target.workQueue,
        doOnResolved: { debugServer in
          self.debugServer = debugServer as? FBDebugServer
        })
  }

  @objc public func debugserver_status() -> FBFuture<AnyObject> {
    return FBFuture.onQueue(
      target.workQueue,
      resolve: {
        guard let debugServer = self.debugServer else {
          return FBControlCoreError.describe("No debug server running").failFuture()
        }
        return FBFuture(result: debugServer as AnyObject)
      })
  }

  @objc public func debugserver_stop() -> FBFuture<AnyObject> {
    return debugserver_status()
      .onQueue(
        target.workQueue,
        fmap: { debugServer in
          self.debugServer!.completed.cancel().mapReplace(debugServer)
        }
      )
      .onQueue(
        target.workQueue,
        doOnResolved: { _ in
          self.debugServer = nil
        })
  }

  @objc public func tail_companion_logs(_ consumer: FBDataConsumer) -> FBFuture<FBLogOperation> {
    return unsafeBitCast(logger.tailToConsumer(consumer), to: FBFuture<FBLogOperation>.self)
  }

  @objc public func diagnostic_information() -> FBFuture<NSDictionary> {
    guard let commands = target as? FBDiagnosticInformationCommands else {
      return FBFuture(result: NSDictionary())
    }
    return commands.fetchDiagnosticInformation()
  }

  public func hid(_ event: NSObject) async throws {
    let hid = try await connectToHID()
    let performSel = NSSelectorFromString("performOnHID:")
    let future = event.perform(performSel, with: hid)!.takeUnretainedValue() as! FBFuture<AnyObject>
    _ = try await bridgeFBFuture(future)
  }

  public func set_hardware_keyboard_enabled(_ enabled: Bool) async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.setHardwareKeyboardEnabled(enabled))
  }

  public func set_preference(_ name: String, value: String, type: String?, domain: String?) async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.setPreference(name, value: value, type: type, domain: domain))
  }

  public func get_preference(_ name: String, domain: String?) async throws -> String {
    let commands = try settingsCommands()
    return try await bridgeFBFuture(commands.getCurrentPreference(name, domain: domain)) as String
  }

  public func set_locale_with_identifier(_ identifier: String) async throws {
    let commands = try settingsCommands()
    try await bridgeFBFutureVoid(commands.setPreference("AppleLocale", value: identifier, type: nil, domain: nil))
  }

  public func get_current_locale_identifier() async throws -> String {
    let commands = try settingsCommands()
    return try await bridgeFBFuture(commands.getCurrentPreference("AppleLocale", domain: nil)) as String
  }

  @objc public func list_locale_identifiers() -> [String] {
    return NSLocale.availableLocaleIdentifiers
  }

  // MARK: - File Commands

  @objc public func move_paths(_ originPaths: [String], to_path destinationPath: String, containerType: String?) -> FBFuture<NSNull> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          let futures = originPaths.map { originPath in
            containerObj.move(from: originPath, to: destinationPath) as! FBFuture<AnyObject>
          }
          return FBFuture<AnyObject>.combine(futures).mapReplace(NSNull())
        }) as! FBFuture<NSNull>
  }

  @objc public func push_file_from_tar(_ tarData: Data, to_path destinationPath: String, containerType: String?) -> FBFuture<NSNull> {
    return (temporaryDirectory.withArchiveExtracted(tarData) as! FBFutureContext<AnyObject>)
      .onQueue(
        target.workQueue,
        pop: { extractionDirectory in
          do {
            let extractDir = extractionDirectory as! URL
            let paths = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            return self.push_files(paths, to_path: destinationPath, containerType: containerType) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<NSNull>
  }

  @objc public func push_files(_ paths: [URL], to_path destinationPath: String, containerType: String?) -> FBFuture<NSNull> {
    return FBFuture.onQueue(
      target.asyncQueue,
      resolve: {
        return self.applicationDataContainerCommands(containerType)
          .onQueue(
            self.target.workQueue,
            pop: { container in
              let containerObj = container as! FBFileContainerProtocol
              let futures = paths.map { originPath in
                containerObj.copy(fromHost: originPath.path, toContainer: destinationPath) as! FBFuture<AnyObject>
              }
              return FBFuture<AnyObject>.combine(futures).mapReplace(NSNull())
            })
      }) as! FBFuture<NSNull>
  }

  @objc public func pull_file_path(_ path: String, destination_path destinationPath: String?, containerType: String?) -> FBFuture<NSString> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          return containerObj.copy(fromContainer: path, toHost: destinationPath!) as! FBFuture<AnyObject>
        }) as! FBFuture<NSString>
  }

  @objc public func pull_file(_ path: String, containerType: String?) -> FBFuture<NSData> {
    var tempPath: String = ""

    return (temporaryDirectory.withTemporaryDirectory() as! FBFutureContext<AnyObject>)
      .onQueue(
        target.workQueue,
        pend: { url in
          let urlObj = url as! URL
          tempPath = (urlObj.path as NSString).appendingPathComponent((path as NSString).lastPathComponent)
          return self.applicationDataContainerCommands(containerType)
            .onQueue(
              self.target.workQueue,
              pop: { container in
                let containerObj = container as! FBFileContainerProtocol
                return containerObj.copy(fromContainer: path, toHost: tempPath) as! FBFuture<AnyObject>
              })
        }
      )
      .onQueue(
        target.workQueue,
        pop: { _ in
          return FBArchiveOperations.createGzippedTarData(forPath: tempPath, queue: self.target.workQueue, logger: self.target.logger!) as! FBFuture<AnyObject>
        }) as! FBFuture<NSData>
  }

  @objc public func tail(_ path: String, to_consumer consumer: FBDataConsumer, in_container containerType: String?) -> FBFuture<FBFuture<NSNull>> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          return containerObj.tail(path, to: consumer) as! FBFuture<AnyObject>
        }) as! FBFuture<FBFuture<NSNull>>
  }

  @objc public func create_directory(_ directoryPath: String, containerType: String) -> FBFuture<NSNull> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          return containerObj.createDirectory(directoryPath) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func remove_paths(_ paths: [String], containerType: String?) -> FBFuture<NSNull> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          let futures = paths.map { path in
            containerObj.remove(path) as! FBFuture<AnyObject>
          }
          return FBFuture<AnyObject>.combine(futures).mapReplace(NSNull())
        }) as! FBFuture<NSNull>
  }

  @objc public func list_path(_ path: String, containerType: String?) -> FBFuture<NSArray> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          return containerObj.contents(ofDirectory: path) as! FBFuture<AnyObject>
        }) as! FBFuture<NSArray>
  }

  @objc public func list_paths(_ paths: [String], containerType: String?) -> FBFuture<NSDictionary> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          let futures = paths.map { path in
            containerObj.contents(ofDirectory: path) as! FBFuture<AnyObject>
          }
          return unsafeBitCast(FBFuture<AnyObject>.combine(futures), to: FBFuture<AnyObject>.self)
        }
      )
      .onQueue(
        target.asyncQueue,
        map: { listings -> AnyObject in
          let listingsArray = listings as! [NSArray]
          return NSDictionary(objects: listingsArray, forKeys: paths as [NSString])
        }) as! FBFuture<NSDictionary>
  }

  public func dapServer(withPath dapPath: String, stdIn: FBProcessInput<AnyObject>, stdOut: any FBDataConsumer) async throws -> FBSubprocess<AnyObject, FBDataConsumer, NSString> {
    guard let commands = target as? AsyncDapServerCommand else {
      throw FBControlCoreError.describe("Target doesn't conform to AsyncDapServerCommand protocol \(target)").build()
    }
    return try await commands.launchDapServer(dapPath, stdIn: stdIn, stdOut: stdOut)
  }

  @objc public func clean() -> FBFuture<NSNull> {
    if target.state == .shutdown {
      return remove_all_storage_and_clear_keychain()
    }
    return uninstall_all_applications()
      .onQueue(
        target.workQueue,
        fmap: { _ in
          self.remove_all_storage_and_clear_keychain() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {
    guard let commands = target as? FBNotificationCommands else {
      throw FBIDBError.describe("\(target) does not conform to FBNotificationCommands").build()
    }
    try await bridgeFBFutureVoid(commands.sendPushNotification(forBundleID: bundleID, jsonPayload: jsonPayload))
  }

  public func simulateMemoryWarning() async throws {
    guard let commands = target as? FBMemoryCommands else {
      throw FBIDBError.describe("\(target) does not conform to FBMemoryCommands").build()
    }
    try await bridgeFBFutureVoid(commands.simulateMemoryWarning())
  }

  // MARK: - Private Methods

  private func applyEnvironmentReplacements(_ environment: [String: String], replacements: [String: String]) -> [String: String] {
    logger.log("Original environment: \(environment)")
    logger.log("Existing replacement mapping: \(replacements)")
    var interpolatedEnvironment: [String: String] = [:]
    for (name, var value) in environment {
      for (interpolationName, interpolationValue) in replacements {
        value = value.replacingOccurrences(of: interpolationName, with: interpolationValue)
      }
      interpolatedEnvironment[name] = value
    }
    logger.log("Interpolated environment: \(interpolatedEnvironment)")
    return interpolatedEnvironment
  }

  private func remove_all_storage_and_clear_keychain() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try storageManager.clean()
      try await clear_keychain()
      return NSNull()
    }
  }

  private func uninstall_all_applications() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      let apps = try await bridgeFBFuture(list_apps(false)) as! [FBInstalledApplication: AnyObject]
      for app in apps.keys where app.installType == .user {
        try await kill_application(app.bundle.identifier)
        try await uninstall_application(app.bundle.identifier)
      }
      return NSNull()
    }
  }

  private func debugserver_prepare(_ bundleID: String) -> FBFuture<AnyObject> {
    return FBFuture.onQueue(
      target.workQueue,
      resolve: {
        if self.debugServer != nil {
          return FBControlCoreError.describe("Debug server is already running").failFuture()
        }
        let persisted = self.storageManager.application.persistedBundles
        guard let bundle = persisted[bundleID] else {
          return FBIDBError.describe("\(bundleID) not persisted application and is therefore not debuggable. Suitable applications: \(FBCollectionInformation.oneLineDescription(from: Array(persisted.keys)))").failFuture()
        }
        return FBFuture(result: bundle as AnyObject)
      })
  }

  private func applicationDataContainerCommands(_ containerType: String?) -> FBFutureContext<AnyObject> {
    if containerType == FBFileContainerKind.crashes.rawValue {
      return target.crashLogFiles() as! FBFutureContext<AnyObject>
    }
    guard let commands = target as? FBFileCommands else {
      return FBControlCoreError.describe("Target doesn't conform to FBFileCommands protocol \(target)").failFutureContext()
    }
    if containerType == FBFileContainerKind.application.rawValue {
      return commands.fileCommandsForApplicationContainers() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.group.rawValue {
      return commands.fileCommandsForGroupContainers() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.media.rawValue {
      return commands.fileCommandsForMediaDirectory() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.root.rawValue {
      return commands.fileCommandsForRootFilesystem() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.provisioningProfiles.rawValue {
      return commands.fileCommandsForProvisioningProfiles() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.mdmProfiles.rawValue {
      return commands.fileCommandsForMDMProfiles() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.springboardIcons.rawValue {
      return commands.fileCommandsForSpringboardIconLayout() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.wallpaper.rawValue {
      return commands.fileCommandsForWallpaper() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.diskImages.rawValue {
      return commands.fileCommandsForDiskImages() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.symbols.rawValue {
      return commands.fileCommandsForSymbols() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.auxillary.rawValue {
      return commands.fileCommandsForAuxillary() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.xctest.rawValue {
      return FBFutureContext(result: storageManager.xctest.asFileContainer() as AnyObject)
    }
    if containerType == FBFileContainerKind.dylib.rawValue {
      return FBFutureContext(result: storageManager.dylib.asFileContainer() as AnyObject)
    }
    if containerType == FBFileContainerKind.dsym.rawValue {
      return FBFutureContext(result: storageManager.dsym.asFileContainer() as AnyObject)
    }
    if containerType == FBFileContainerKind.framework.rawValue {
      return FBFutureContext(result: storageManager.framework.asFileContainer() as AnyObject)
    }
    if containerType == nil || containerType?.isEmpty == true {
      return target is FBDevice ? commands.fileCommandsForMediaDirectory() as! FBFutureContext<AnyObject> : commands.fileCommandsForRootFilesystem() as! FBFutureContext<AnyObject>
    }
    return commands.fileCommandsForContainerApplication(containerType!) as! FBFutureContext<AnyObject>
  }

  private func lifecycleCommands() throws -> any FBSimulatorLifecycleCommandsProtocol {
    guard let commands = target as? FBSimulatorLifecycleCommandsProtocol else {
      throw FBIDBError.describe("Target doesn't conform to FBSimulatorLifecycleCommands protocol \(target)").build()
    }
    return commands
  }

  private func mediaCommands() throws -> any FBSimulatorMediaCommandsProtocol {
    guard let commands = target as? FBSimulatorMediaCommandsProtocol else {
      throw FBIDBError.describe("Target doesn't conform to FBSimulatorMediaCommands protocol \(target)").build()
    }
    return commands
  }

  private func keychainCommands() throws -> any FBSimulatorKeychainCommandsProtocol {
    guard let commands = target as? FBSimulatorKeychainCommandsProtocol else {
      throw FBIDBError.describe("Target doesn't conform to FBSimulatorKeychainCommands protocol \(target)").build()
    }
    return commands
  }

  private func settingsCommands() throws -> any FBSimulatorSettingsCommandsProtocol {
    guard let commands = target as? (any FBSimulatorSettingsCommandsProtocol) else {
      throw FBIDBError.describe("Target doesn't conform to FBSimulatorSettingsCommands protocol \(target)").build()
    }
    return commands
  }

  private func connectToHID() async throws -> FBSimulatorHID {
    let commands = try lifecycleCommands()
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(target.logger)
    return try await bridgeFBFuture(commands.connectToHID())
  }

  private func installExtractedApp(_ extractedAppContext: FBFutureContext<AnyObject>, makeDebuggable: Bool) -> FBFuture<FBInstalledArtifact> {
    let bundleContext =
      extractedAppContext
      .onQueue(
        target.asyncQueue,
        pend: { extractPath in
          do {
            let url = extractPath as! URL
            guard let bundleDescriptor = try? FBBundleDescriptor.findAppPath(fromDirectory: url, logger: self.target.logger) else {
              return FBFuture(error: FBControlCoreError.describe("No app bundle could be extracted").build() as NSError)
            }
            return FBFuture(result: bundleDescriptor as AnyObject)
          }
        })
    return installAppBundle(bundleContext, makeDebuggable: makeDebuggable)
  }

  private func installAppBundle(_ bundleContext: FBFutureContext<AnyObject>, makeDebuggable: Bool) -> FBFuture<FBInstalledArtifact> {
    let userDevelopmentAppIsRequired = target is FBDevice

    return
      bundleContext
      .onQueue(
        target.asyncQueue,
        pop: { bundle in
          guard let appBundle = bundle as? FBBundleDescriptor else {
            return FBIDBError.describe("No app bundle could be extracted").failFuture()
          }
          do {
            try self.storageManager.application.checkArchitecture(appBundle)
          } catch {
            return FBFuture(error: error as NSError)
          }
          return FBFuture<AnyObject>.combine([
            self.target.installApplication(withPath: appBundle.path) as! FBFuture<AnyObject>,
            // TODO: currently we have to persist it even if app is not used for debugging
            // as installed apps are referenced from xctestrun files and expanded by idb
            // by using its own application storage. Fix this by replacing xctestrun
            // placeholders by app bundle paths instead
            self.storageManager.application.saveBundle(appBundle) as! FBFuture<AnyObject>,
          ])
          .onQueue(
            self.target.asyncQueue,
            fmap: { results -> FBFuture<AnyObject> in
              let tuple = results as [AnyObject]
              let installedApp = tuple[0] as! FBInstalledApplication
              if makeDebuggable && installedApp.installType != .userDevelopment && userDevelopmentAppIsRequired {
                return FBIDBError.describe("Requested debuggable install of \(installedApp) but User Development signing is required").failFuture()
              }
              return FBFuture(result: FBInstalledArtifact(name: appBundle.identifier, uuid: appBundle.binary?.uuid as NSUUID?, path: URL(fileURLWithPath: installedApp.bundle.path)) as AnyObject)
            })
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func installXctest(_ extractedXctest: FBFutureContext<AnyObject>, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    return
      extractedXctest
      .onQueue(
        target.workQueue,
        pop: { extractionDirectory in
          let dir = extractionDirectory as! URL
          return self.storageManager.xctest.saveBundleOrTestRunFromBaseDirectory(dir, skipSigningBundles: skipSigningBundles) as! FBFuture<AnyObject>
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func installXctestFilePath(_ bundle: FBFutureContext<AnyObject>, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    return
      bundle
      .onQueue(
        target.workQueue,
        pop: { xctestURL in
          let url = xctestURL as! URL
          return self.storageManager.xctest.saveBundleOrTestRun(url, skipSigningBundles: skipSigningBundles) as! FBFuture<AnyObject>
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func installFile(_ extractedFileContext: FBFutureContext<AnyObject>, intoStorage storage: FBFileStorage) -> FBFuture<FBInstalledArtifact> {
    return
      extractedFileContext
      .onQueue(
        target.workQueue,
        pop: { extractedFile in
          do {
            let url = extractedFile as! URL
            let artifact = try storage.saveFile(url)
            return FBFuture(result: artifact) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func dsymDirnameFromUnzipDir(_ extractedFileContext: FBFutureContext<AnyObject>) -> FBFutureContext<AnyObject> {
    return
      extractedFileContext
      .onQueue(
        target.workQueue,
        pend: { parentDir in
          do {
            let dir = parentDir as! URL
            let subDirs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            if subDirs.count != 1 {
              return FBFuture(result: dir as AnyObject)
            }
            return FBFuture(result: subDirs[0] as AnyObject)
          } catch {
            return FBFuture(error: error as NSError)
          }
        })
  }

  private func installAndLinkDsym(_ extractedFileContext: FBFutureContext<AnyObject>, intoStorage storage: FBFileStorage, linkTo: FBDsymInstallLinkToBundle?) -> FBFuture<FBInstalledArtifact> {
    return
      extractedFileContext
      .onQueue(
        target.workQueue,
        pop: { extractionDir in
          do {
            let dir = extractionDir as! URL
            let artifact = try storage.saveFileInUniquePath(dir)

            guard let linkTo else {
              return FBFuture(result: artifact) as! FBFuture<AnyObject>
            }

            let future: FBFuture<AnyObject>
            if linkTo.bundle_type == .app {
              future =
                self.target.installedApplication(withBundleID: linkTo.bundle_id)
                .onQueue(
                  self.target.workQueue,
                  map: { linkToApp -> AnyObject in
                    let app = linkToApp
                    self.logger.log("Going to create a symlink for app bundle: \(app.bundle.name)")
                    return URL(fileURLWithPath: app.bundle.path) as NSURL
                  })
            } else {
              let testDescriptor = try self.storageManager.xctest.testDescriptor(withID: linkTo.bundle_id)
              self.logger.log("Going to create a symlink for test bundle: \(testDescriptor.name)")
              future = FBFuture(result: testDescriptor.url as AnyObject)
            }

            return
              future
              .onQueue(
                self.target.workQueue,
                fmap: { bundlePath in
                  do {
                    let bundlePathURL = bundlePath as! URL
                    let bundleUrl = bundlePathURL.deletingLastPathComponent()
                    let dsymURL = bundleUrl.appendingPathComponent(artifact.path.lastPathComponent)
                    try? FileManager.default.removeItem(at: dsymURL)
                    self.logger.log("Deleted a symlink for dsym if it already exists: \(dsymURL)")
                    try FileManager.default.createSymbolicLink(at: dsymURL, withDestinationURL: artifact.path)
                    self.logger.log("Created a symlink for dsym from: \(dsymURL) to \(artifact.path)")
                    return FBFuture(result: artifact) as! FBFuture<AnyObject>
                  } catch {
                    return FBFuture(error: error as NSError)
                  }
                })
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func installBundle(_ extractedDirectoryContext: FBFutureContext<AnyObject>, intoStorage storage: FBBundleStorage) -> FBFuture<FBInstalledArtifact> {
    return
      extractedDirectoryContext
      .onQueue(
        target.workQueue,
        pop: { extractedDirectory in
          do {
            let dir = extractedDirectory as! URL
            let bundle = try FBStorageUtils.bundle(inDirectory: dir)
            return storage.saveBundle(bundle) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<FBInstalledArtifact>
  }
}
