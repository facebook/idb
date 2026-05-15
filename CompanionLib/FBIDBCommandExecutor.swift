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

  private let target: any FBiOSTarget & AsynciOSTarget
  private let logger: FBIDBLogger
  private let debugserverPort: in_port_t

  @objc public let storageManager: FBIDBStorageManager
  @objc public var debugServer: FBDebugServer?
  @objc public let temporaryDirectory: FBTemporaryDirectory

  // MARK: - Initializers

  @objc public static func commandExecutor(forTarget target: FBiOSTarget, storageManager: FBIDBStorageManager, temporaryDirectory: FBTemporaryDirectory, debugserverPort: in_port_t, logger: FBIDBLogger) -> FBIDBCommandExecutor {
    let asyncTarget = target as! any FBiOSTarget & AsynciOSTarget
    return FBIDBCommandExecutor(target: asyncTarget, storageManager: storageManager, temporaryDirectory: temporaryDirectory, debugserverPort: debugserverPort, logger: logger.withName("grpc_handler") as! FBIDBLogger)
  }

  private init(target: any FBiOSTarget & AsynciOSTarget, storageManager: FBIDBStorageManager, temporaryDirectory: FBTemporaryDirectory, debugserverPort: in_port_t, logger: FBIDBLogger) {
    self.target = target
    self.storageManager = storageManager
    self.temporaryDirectory = temporaryDirectory
    self.debugserverPort = debugserverPort
    self.logger = logger
    super.init()
  }

  // MARK: - Installation

  public func list_apps(_ fetchProcessState: Bool) async throws -> [FBInstalledApplication: Any] {
    let installedApps = try await target.installedApplications()
    let runningApps: [String: pid_t]
    if fetchProcessState {
      runningApps = try await target.runningApplications()
    } else {
      runningApps = [:]
    }
    var listing: [FBInstalledApplication: Any] = [:]
    for application in installedApps {
      if let pid = runningApps[application.bundle.identifier] {
        listing[application] = NSNumber(value: pid)
      } else {
        listing[application] = NSNull()
      }
    }
    return listing
  }

  public func install_app_file_path(_ filePath: String, make_debuggable makeDebuggable: Bool, override_modification_time overrideModificationTime: Bool) async throws -> FBInstalledArtifact {
    if FBBundleDescriptor.isApplication(atPath: filePath) {
      let bundleDescriptor = try FBBundleDescriptor.bundle(fromPath: filePath)
      return try await installAppBundle(bundleDescriptor, makeDebuggable: makeDebuggable)
    } else {
      return try await withFBFutureContext(temporaryDirectory.withArchiveExtracted(fromFile: filePath, overrideModificationTime: overrideModificationTime) as! FBFutureContext<AnyObject>) { extractPath in
        let url = extractPath as! URL
        return try await installExtractedApp(url, makeDebuggable: makeDebuggable)
      }
    }
  }

  public func install_app_stream(_ input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, make_debuggable makeDebuggable: Bool, override_modification_time overrideModificationTime: Bool) async throws -> FBInstalledArtifact {
    return try await withFBFutureContext(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: compression, overrideModificationTime: overrideModificationTime) as! FBFutureContext<AnyObject>) { extractPath in
      let url = extractPath as! URL
      return try await installExtractedApp(url, makeDebuggable: makeDebuggable)
    }
  }

  public func install_xctest_app_file_path(_ filePath: String, skipSigningBundles: Bool) async throws -> FBInstalledArtifact {
    return try await installXctestFilePath(URL(fileURLWithPath: filePath), skipSigningBundles: skipSigningBundles)
  }

  public func install_xctest_app_stream(_ stream: FBProcessInput<AnyObject>, skipSigningBundles: Bool) async throws -> FBInstalledArtifact {
    return try await withFBFutureContext(temporaryDirectory.withArchiveExtracted(fromStream: stream, compression: .GZIP) as! FBFutureContext<AnyObject>) { extractPath in
      let url = extractPath as! URL
      return try await installXctest(url, skipSigningBundles: skipSigningBundles)
    }
  }

  public func install_dylib_file_path(_ filePath: String) async throws -> FBInstalledArtifact {
    return try await installFile(URL(fileURLWithPath: filePath), intoStorage: storageManager.dylib)
  }

  public func install_dylib_stream(_ input: FBProcessInput<AnyObject>, name: String) async throws -> FBInstalledArtifact {
    return try await withFBFutureContext(temporaryDirectory.withGzipExtracted(fromStream: input, name: name) as! FBFutureContext<AnyObject>) { extractPath in
      let url = extractPath as! URL
      return try await installFile(url, intoStorage: storageManager.dylib)
    }
  }

  public func install_framework_file_path(_ filePath: String) async throws -> FBInstalledArtifact {
    return try await installBundle(URL(fileURLWithPath: filePath), intoStorage: storageManager.framework)
  }

  public func install_framework_stream(_ input: FBProcessInput<AnyObject>) async throws -> FBInstalledArtifact {
    return try await withFBFutureContext(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: .GZIP) as! FBFutureContext<AnyObject>) { extractPath in
      let url = extractPath as! URL
      return try await installBundle(url, intoStorage: storageManager.framework)
    }
  }

  public func install_dsym_file_path(_ filePath: String, linkTo: FBDsymInstallLinkToBundle?) async throws -> FBInstalledArtifact {
    return try await installAndLinkDsym(URL(fileURLWithPath: filePath), intoStorage: storageManager.dsym, linkTo: linkTo)
  }

  public func install_dsym_stream(_ input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, linkTo: FBDsymInstallLinkToBundle?) async throws -> FBInstalledArtifact {
    return try await withFBFutureContext(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: compression) as! FBFutureContext<AnyObject>) { extractPath in
      let url = try dsymDirnameFromUnzipDir(extractPath as! URL)
      return try await installAndLinkDsym(url, intoStorage: storageManager.dsym, linkTo: linkTo)
    }
  }

  // MARK: - Public Methods

  public func take_screenshot(_ format: FBScreenshotFormat) async throws -> Data {
    try await target.takeScreenshot(format: format)
  }

  public func accessibility_info_at_point(_ value: NSValue?, nestedFormat: Bool) async throws -> FBAccessibilityElementsResponse {
    guard let simulator = target as? FBSimulator else {
      throw FBIDBError.describe("Target is not a simulator, cannot provide accessibility commands: \(target)").build()
    }
    let options = FBAccessibilityRequestOptions.`default`()
    options.nestedFormat = nestedFormat
    options.enableLogging = true

    let element: FBAccessibilityElement
    if let value {
      element = try await simulator.accessibilityElement(at: value.pointValue)
    } else {
      element = try await simulator.accessibilityElementForFrontmostApplication()
    }
    defer { element.close() }
    return try element.serialize(with: options)
  }

  public func add_media(_ filePaths: [URL]) async throws {
    try await simulatorTarget().addMedia(filePaths)
  }

  public func set_location(_ latitude: Double, longitude: Double) async throws {
    try await target.overrideLocation(longitude: longitude, latitude: latitude)
  }

  public func clear_keychain() async throws {
    try await simulatorTarget().clearKeychain()
  }

  public func approve(_ services: Set<FBTargetSettingsService>, for_application bundleID: String) async throws {
    try await simulatorTarget().grantAccess(Set([bundleID]), toServices: services)
  }

  public func revoke(_ services: Set<FBTargetSettingsService>, for_application bundleID: String) async throws {
    try await simulatorTarget().revokeAccess(Set([bundleID]), toServices: services)
  }

  public func approve_deeplink(_ scheme: String, for_application bundleID: String) async throws {
    try await simulatorTarget().grantAccess(Set([bundleID]), toDeeplink: scheme)
  }

  public func revoke_deeplink(_ scheme: String, for_application bundleID: String) async throws {
    try await simulatorTarget().revokeAccess(Set([bundleID]), toDeeplink: scheme)
  }

  public func open_url(_ url: String) async throws {
    try await simulatorTarget().open(URL(string: url)!)
  }

  public func focus() async throws {
    try await simulatorTarget().focus()
  }

  public func update_contacts(_ dbTarData: Data) async throws {
    let simulator = try simulatorTarget()
    try await withFBFutureContext(temporaryDirectory.withArchiveExtracted(dbTarData)) { tempDir in
      try await simulator.updateContacts((tempDir as URL).path)
    }
  }

  public func clear_contacts() async throws {
    try await simulatorTarget().clearContacts()
  }

  public func clear_photos() async throws {
    try await simulatorTarget().clearPhotos()
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
    return try await simulatorTarget().listTests(forBundleAtPath: testDescriptor.url.path, timeout: FBIDBCommandExecutor.ListTestBundleTimeout, withAppAtPath: finalAppPath)
  }

  public func uninstall_application(_ bundleID: String) async throws {
    try await target.uninstallApplication(bundleID: bundleID)
  }

  public func kill_application(_ bundleID: String) async throws {
    do {
      try await target.killApplication(bundleID: bundleID)
    } catch {
      // Mirror the legacy `.fallback(NSNull())` behavior — kill is a no-op when
      // the app isn't running.
    }
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
    return try await target.launchApplication(derived)
  }

  public func crash_list(_ predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    return try await target.crashes(matching: predicate, useCache: false)
  }

  public func crash_show(_ predicate: NSPredicate) async throws -> FBCrashLog {
    let crashArray = try await target.crashes(matching: predicate, useCache: true)
    if crashArray.count > 1 {
      throw FBIDBError.describe("More than one crash log matching \(predicate)").build()
    }
    guard let first = crashArray.first else {
      throw FBIDBError.describe("No crashes matching \(predicate)").build()
    }
    return try first.obtainCrashLog()
  }

  public func crash_delete(_ predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    return try await target.pruneCrashes(matching: predicate)
  }

  public func xctest_run(_ request: FBXCTestRunRequest, reporter: FBXCTestReporter, logger: FBControlCoreLogger) async throws -> FBIDBTestOperation {
    return try await request.startAsync(withBundleStorageManager: storageManager.xctest, target: target, reporter: reporter, logger: logger, temporaryDirectory: temporaryDirectory)
  }

  public func debugserver_start(_ bundleID: String) async throws -> FBDebugServer {
    let bundle = try debugserver_prepare(bundleID)
    let server = try await target.launchDebugServer(forHostApplication: bundle, port: debugserverPort)
    debugServer = server
    return server
  }

  public func debugserver_status() throws -> FBDebugServer {
    guard let debugServer else {
      throw FBControlCoreError.describe("No debug server running").build()
    }
    return debugServer
  }

  public func debugserver_stop() async throws -> FBDebugServer {
    let server = try debugserver_status()
    try await server.cancelAsync()
    debugServer = nil
    return server
  }

  public func tail_companion_logs(_ consumer: FBDataConsumer) async throws -> FBLogOperation {
    return try await logger.tailToConsumerAsync(consumer)
  }

  public func diagnostic_information() async throws -> NSDictionary {
    guard let device = target as? FBDevice else {
      return NSDictionary()
    }
    return try await device.fetchDiagnosticInformation() as NSDictionary
  }

  public func hid(_ event: NSObject) async throws {
    let hid = try await connectToHID()
    guard let hidEvent = event as? FBSimulatorHIDEventProtocol else {
      throw FBIDBError.describe("Event \(event) does not conform to FBSimulatorHIDEventProtocol").build()
    }
    try await hidEvent.sendAsync(on: hid)
  }

  public func set_hardware_keyboard_enabled(_ enabled: Bool) async throws {
    try await simulatorTarget().setSetting(.hardwareKeyboard, enabled: enabled)
  }

  public func set_preference(_ name: String, value: String, type: String?, domain: String?) async throws {
    try await simulatorTarget().setPreference(name, value: value, type: type, domain: domain)
  }

  public func get_preference(_ name: String, domain: String?) async throws -> String {
    try await simulatorTarget().getCurrentPreference(name, domain: domain)
  }

  public func set_locale_with_identifier(_ identifier: String) async throws {
    try await simulatorTarget().setPreference("AppleLocale", value: identifier, type: nil, domain: nil)
  }

  public func get_current_locale_identifier() async throws -> String {
    try await simulatorTarget().getCurrentPreference("AppleLocale", domain: nil)
  }

  @objc public func list_locale_identifiers() -> [String] {
    return NSLocale.availableLocaleIdentifiers
  }

  // MARK: - File Commands

  public func move_paths(_ originPaths: [String], to_path destinationPath: String, containerType: String?) async throws {
    try await withFileContainer(for: containerType) { container in
      for originPath in originPaths {
        try await container.move(from: originPath, to: destinationPath)
      }
    }
  }

  public func push_file_from_tar(_ tarData: Data, to_path destinationPath: String, containerType: String?) async throws {
    try await withFBFutureContext(temporaryDirectory.withArchiveExtracted(tarData)) { extractDir in
      let paths = try FileManager.default.contentsOfDirectory(at: extractDir as URL, includingPropertiesForKeys: [.isDirectoryKey], options: [])
      try await self.push_files(paths, to_path: destinationPath, containerType: containerType)
    }
  }

  public func push_files(_ paths: [URL], to_path destinationPath: String, containerType: String?) async throws {
    try await withFileContainer(for: containerType) { container in
      for originPath in paths {
        try await container.copy(fromHost: originPath.path, toContainer: destinationPath)
      }
    }
  }

  public func pull_file_path(_ path: String, destination_path destinationPath: String?, containerType: String?) async throws -> String {
    return try await withFileContainer(for: containerType) { container in
      try await container.copy(fromContainer: path, toHost: destinationPath!)
    }
  }

  public func pull_file(_ path: String, containerType: String?) async throws -> Data {
    return try await withFBFutureContext(temporaryDirectory.withTemporaryDirectory()) { url in
      let tempPath = ((url as URL).path as NSString).appendingPathComponent((path as NSString).lastPathComponent)
      try await self.withFileContainer(for: containerType) { container in
        _ = try await container.copy(fromContainer: path, toHost: tempPath)
      }
      return try await FBArchiveOperations.createGzippedTarDataAsync(forPath: tempPath, queue: self.target.workQueue, logger: self.target.logger!)
    }
  }

  public func tail(_ path: String, to_consumer consumer: FBDataConsumer, in_container containerType: String?) async throws -> any FBiOSTargetOperation {
    return try await withFileContainer(for: containerType) { container in
      try await container.tail(path, to: consumer)
    }
  }

  public func create_directory(_ directoryPath: String, containerType: String) async throws {
    try await withFileContainer(for: containerType) { container in
      try await container.createDirectory(directoryPath)
    }
  }

  public func remove_paths(_ paths: [String], containerType: String?) async throws {
    try await withFileContainer(for: containerType) { container in
      for path in paths {
        try await container.remove(path)
      }
    }
  }

  public func list_path(_ path: String, containerType: String?) async throws -> [String] {
    return try await withFileContainer(for: containerType) { container in
      try await container.contents(ofDirectory: path)
    }
  }

  public func list_paths(_ paths: [String], containerType: String?) async throws -> [String: [String]] {
    return try await withFileContainer(for: containerType) { container in
      var result: [String: [String]] = [:]
      for path in paths {
        let listing: [String] = try await container.contents(ofDirectory: path)
        result[path] = listing
      }
      return result
    }
  }

  public func dapServer(withPath dapPath: String, stdIn: FBProcessInput<AnyObject>, stdOut: any FBDataConsumer) async throws -> FBSubprocess<AnyObject, FBDataConsumer, NSString> {
    return try await simulatorTarget().launchDapServer(dapPath, stdIn: stdIn, stdOut: stdOut)
  }

  public func clean() async throws {
    if target.state != .shutdown {
      try await uninstall_all_applications()
    }
    try await remove_all_storage_and_clear_keychain()
  }

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {
    try await simulatorTarget().sendPushNotification(forBundleID: bundleID, jsonPayload: jsonPayload)
  }

  public func simulateMemoryWarning() async throws {
    try await simulatorTarget().simulateMemoryWarning()
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

  private func remove_all_storage_and_clear_keychain() async throws {
    try storageManager.clean()
    try await clear_keychain()
  }

  private func uninstall_all_applications() async throws {
    let apps = try await list_apps(false)
    for app in apps.keys where app.installType == .user {
      try await kill_application(app.bundle.identifier)
      try await uninstall_application(app.bundle.identifier)
    }
  }

  private func debugserver_prepare(_ bundleID: String) throws -> FBBundleDescriptor {
    if debugServer != nil {
      throw FBControlCoreError.describe("Debug server is already running").build()
    }
    let persisted = storageManager.application.persistedBundles
    guard let bundle = persisted[bundleID] else {
      throw FBIDBError.describe("\(bundleID) not persisted application and is therefore not debuggable. Suitable applications: \(FBCollectionInformation.oneLineDescription(from: Array(persisted.keys)))").build()
    }
    return bundle
  }

  private func withFileContainer<R>(
    for containerType: String?,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    if containerType == FBFileContainerKind.crashes.rawValue {
      return try await target.withCrashLogFiles { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.xctest.rawValue {
      return try await body(AsyncFileContainerAdapter(storageManager.xctest.asFileContainer()))
    }
    if containerType == FBFileContainerKind.dylib.rawValue {
      return try await body(AsyncFileContainerAdapter(storageManager.dylib.asFileContainer()))
    }
    if containerType == FBFileContainerKind.dsym.rawValue {
      return try await body(AsyncFileContainerAdapter(storageManager.dsym.asFileContainer()))
    }
    if containerType == FBFileContainerKind.framework.rawValue {
      return try await body(AsyncFileContainerAdapter(storageManager.framework.asFileContainer()))
    }
    if containerType == FBFileContainerKind.application.rawValue {
      return try await target.withFileCommandsForApplicationContainers { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.group.rawValue {
      return try await target.withFileCommandsForGroupContainers { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.media.rawValue {
      return try await target.withFileCommandsForMediaDirectory { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.root.rawValue {
      return try await target.withFileCommandsForRootFilesystem { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.provisioningProfiles.rawValue {
      return try await target.withFileCommandsForProvisioningProfiles { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.mdmProfiles.rawValue {
      return try await target.withFileCommandsForMDMProfiles { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.springboardIcons.rawValue {
      return try await target.withFileCommandsForSpringboardIconLayout { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.wallpaper.rawValue {
      return try await target.withFileCommandsForWallpaper { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.diskImages.rawValue {
      return try await target.withFileCommandsForDiskImages { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.symbols.rawValue {
      return try await target.withFileCommandsForSymbols { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == FBFileContainerKind.auxillary.rawValue {
      return try await target.withFileCommandsForAuxillary { container in
        try await body(AsyncFileContainerAdapter(container))
      }
    }
    if containerType == nil || containerType?.isEmpty == true {
      if target is FBDevice {
        return try await target.withFileCommandsForMediaDirectory { container in
          try await body(AsyncFileContainerAdapter(container))
        }
      } else {
        return try await target.withFileCommandsForRootFilesystem { container in
          try await body(AsyncFileContainerAdapter(container))
        }
      }
    }
    return try await target.withFileCommandsForContainerApplication(containerType!) { container in
      try await body(AsyncFileContainerAdapter(container))
    }
  }

  private func simulatorTarget() throws -> FBSimulator {
    guard let simulator = target as? FBSimulator else {
      throw FBIDBError.describe("Target is not a simulator: \(target)").build()
    }
    return simulator
  }

  private func connectToHID() async throws -> FBSimulatorHID {
    let simulator = try simulatorTarget()
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(target.logger)
    return try await simulator.connectToHID()
  }

  private func installExtractedApp(_ extractPath: URL, makeDebuggable: Bool) async throws -> FBInstalledArtifact {
    guard let bundleDescriptor = try? FBBundleDescriptor.findAppPath(fromDirectory: extractPath, logger: target.logger) else {
      throw FBControlCoreError.describe("No app bundle could be extracted").build()
    }
    return try await installAppBundle(bundleDescriptor, makeDebuggable: makeDebuggable)
  }

  private func installAppBundle(_ appBundle: FBBundleDescriptor, makeDebuggable: Bool) async throws -> FBInstalledArtifact {
    let userDevelopmentAppIsRequired = target is FBDevice
    try storageManager.application.checkArchitecture(appBundle)
    let installedApp = try await target.installApplication(atPath: appBundle.path)
    // TODO: currently we have to persist it even if app is not used for debugging
    // as installed apps are referenced from xctestrun files and expanded by idb
    // by using its own application storage. Fix this by replacing xctestrun
    // placeholders by app bundle paths instead
    _ = try await storageManager.application.saveBundleAsync(appBundle)
    if makeDebuggable && installedApp.installType != .userDevelopment && userDevelopmentAppIsRequired {
      throw FBIDBError.describe("Requested debuggable install of \(installedApp) but User Development signing is required").build()
    }
    return FBInstalledArtifact(name: appBundle.identifier, uuid: appBundle.binary?.uuid as NSUUID?, path: URL(fileURLWithPath: installedApp.bundle.path))
  }

  private func installXctest(_ extractionDirectory: URL, skipSigningBundles: Bool) async throws -> FBInstalledArtifact {
    return try await storageManager.xctest.saveBundleOrTestRunFromBaseDirectoryAsync(extractionDirectory, skipSigningBundles: skipSigningBundles)
  }

  private func installXctestFilePath(_ xctestURL: URL, skipSigningBundles: Bool) async throws -> FBInstalledArtifact {
    return try await storageManager.xctest.saveBundleOrTestRunAsync(xctestURL, skipSigningBundles: skipSigningBundles)
  }

  private func installFile(_ extractedFile: URL, intoStorage storage: FBFileStorage) async throws -> FBInstalledArtifact {
    return try storage.saveFile(extractedFile)
  }

  private func dsymDirnameFromUnzipDir(_ parentDir: URL) throws -> URL {
    let subDirs = try FileManager.default.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
    if subDirs.count != 1 {
      return parentDir
    }
    return subDirs[0]
  }

  private func installAndLinkDsym(_ extractionDir: URL, intoStorage storage: FBFileStorage, linkTo: FBDsymInstallLinkToBundle?) async throws -> FBInstalledArtifact {
    let artifact = try storage.saveFileInUniquePath(extractionDir)
    guard let linkTo else {
      return artifact
    }
    let bundlePathURL: URL
    if linkTo.bundle_type == .app {
      let app = try await target.installedApplication(bundleID: linkTo.bundle_id)
      logger.log("Going to create a symlink for app bundle: \(app.bundle.name)")
      bundlePathURL = URL(fileURLWithPath: app.bundle.path)
    } else {
      let testDescriptor = try storageManager.xctest.testDescriptor(withID: linkTo.bundle_id)
      logger.log("Going to create a symlink for test bundle: \(testDescriptor.name)")
      bundlePathURL = testDescriptor.url
    }
    let bundleUrl = bundlePathURL.deletingLastPathComponent()
    let dsymURL = bundleUrl.appendingPathComponent(artifact.path.lastPathComponent)
    try? FileManager.default.removeItem(at: dsymURL)
    logger.log("Deleted a symlink for dsym if it already exists: \(dsymURL)")
    try FileManager.default.createSymbolicLink(at: dsymURL, withDestinationURL: artifact.path)
    logger.log("Created a symlink for dsym from: \(dsymURL) to \(artifact.path)")
    return artifact
  }

  private func installBundle(_ extractedDirectory: URL, intoStorage storage: FBBundleStorage) async throws -> FBInstalledArtifact {
    let bundle = try FBStorageUtils.bundle(inDirectory: extractedDirectory)
    return try await storage.saveBundleAsync(bundle)
  }
}
