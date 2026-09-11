/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
internal import FBDeviceControl
import FBSimulatorControl
import Foundation
import SimulatorXCTest
import XCTestBootstrap

public enum IDBCommandError: Error {
  case simulatorOnlyOperation(operation: String, targetDescription: String)
  case notASimulator(targetDescription: String)
  case invalidURL(urlString: String)
  case multipleCrashLogs(predicateDescription: String)
  case noCrashLogs(predicateDescription: String)
  case replTestsUnsupported(targetDescription: String)
  case replSessionsUnsupported(targetDescription: String)
  case replAppLaunchesUnsupported(targetDescription: String)
  case replHostAppMissing
  case noDebugServer
  case debugServerAlreadyRunning
  case notPersistedApplication(bundleID: String, suitable: [String])
  case noAppBundleExtracted
  case userDevelopmentSigningRequired(applicationDescription: String)
}

extension IDBCommandError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .simulatorOnlyOperation(operation, targetDescription):
      return "Target is not a simulator, cannot \(operation): \(targetDescription)"
    case let .notASimulator(targetDescription):
      return "Target is not a simulator: \(targetDescription)"
    case let .invalidURL(urlString):
      return "\(urlString) is not a valid URL"
    case let .multipleCrashLogs(predicateDescription):
      return "More than one crash log matching \(predicateDescription)"
    case let .noCrashLogs(predicateDescription):
      return "No crashes matching \(predicateDescription)"
    case let .replTestsUnsupported(targetDescription):
      return "\(targetDescription) does not support running REPL tests"
    case let .replSessionsUnsupported(targetDescription):
      return "\(targetDescription) does not support running REPL sessions"
    case let .replAppLaunchesUnsupported(targetDescription):
      return "\(targetDescription) does not support REPL app launches"
    case .replHostAppMissing:
      return "ReplHost.app not found in the companion Resources directory"
    case .noDebugServer:
      return "No debug server running"
    case .debugServerAlreadyRunning:
      return "Debug server is already running"
    case let .notPersistedApplication(bundleID, suitable):
      return "\(bundleID) not persisted application and is therefore not debuggable. Suitable applications: \(CollectionInformation.oneLineDescription(from: suitable))"
    case .noAppBundleExtracted:
      return "No app bundle could be extracted"
    case let .userDevelopmentSigningRequired(applicationDescription):
      return "Requested debuggable install of \(applicationDescription) but User Development signing is required"
    }
  }
}

public final class IDBCommandExecutor {

  private let target: any FBiOSTarget
  private let logger: IDBLogger
  private let debugserverPort: in_port_t

  public let storageManager: IDBStorageManager
  public var debugServer: DebugServer?
  public let temporaryDirectory: FBTemporaryDirectory

  // MARK: - Initializers

  public static func commandExecutor(forTarget target: any FBiOSTarget, storageManager: IDBStorageManager, temporaryDirectory: FBTemporaryDirectory, debugserverPort: in_port_t, logger: IDBLogger) -> IDBCommandExecutor {
    IDBCommandExecutor(target: target, storageManager: storageManager, temporaryDirectory: temporaryDirectory, debugserverPort: debugserverPort, logger: logger.named("grpc_handler"))
  }

  private init(target: any FBiOSTarget, storageManager: IDBStorageManager, temporaryDirectory: FBTemporaryDirectory, debugserverPort: in_port_t, logger: IDBLogger) {
    self.target = target
    self.storageManager = storageManager
    self.temporaryDirectory = temporaryDirectory
    self.debugserverPort = debugserverPort
    self.logger = logger
  }

  // MARK: - Installation

  public func list_apps(_ fetchProcessState: Bool) async throws -> [FBInstalledApplication: Any] {
    let installedApps = try await target.application.installed()
    let runningApps: [String: pid_t]
    if fetchProcessState {
      runningApps = try await target.application.running()
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

  public func install_app_file_path(_ filePath: String, make_debuggable makeDebuggable: Bool, override_modification_time overrideModificationTime: Bool) async throws -> InstalledArtifact {
    if FBBundleDescriptor.isApplication(atPath: filePath) {
      let bundleDescriptor = try FBBundleDescriptor.bundle(fromPath: filePath)
      return try await installAppBundle(bundleDescriptor, makeDebuggable: makeDebuggable)
    } else {
      return try await temporaryDirectory.withArchiveExtracted(fromFile: filePath, overrideModificationTime: overrideModificationTime) { extractPath in
        return try await installExtractedApp(extractPath, makeDebuggable: makeDebuggable)
      }
    }
  }

  public func install_app_stream(_ input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, make_debuggable makeDebuggable: Bool, override_modification_time overrideModificationTime: Bool) async throws -> InstalledArtifact {
    return try await temporaryDirectory.withArchiveExtracted(fromStream: input, compression: compression, overrideModificationTime: overrideModificationTime) { extractPath in
      return try await installExtractedApp(extractPath, makeDebuggable: makeDebuggable)
    }
  }

  public func install_xctest_app_file_path(_ filePath: String, skipSigningBundles: Bool) async throws -> InstalledArtifact {
    return try await installXctestFilePath(URL(fileURLWithPath: filePath), skipSigningBundles: skipSigningBundles)
  }

  public func install_xctest_app_stream(_ stream: FBProcessInput<AnyObject>, skipSigningBundles: Bool) async throws -> InstalledArtifact {
    return try await temporaryDirectory.withArchiveExtracted(fromStream: stream, compression: .GZIP) { extractPath in
      return try await installXctest(extractPath, skipSigningBundles: skipSigningBundles)
    }
  }

  public func install_dylib_file_path(_ filePath: String) async throws -> InstalledArtifact {
    return try await installFile(URL(fileURLWithPath: filePath), intoStorage: storageManager.dylib)
  }

  public func install_dylib_stream(_ input: FBProcessInput<AnyObject>, name: String) async throws -> InstalledArtifact {
    return try await temporaryDirectory.withGzipExtracted(fromStream: input, name: name) { extractPath in
      return try await installFile(extractPath, intoStorage: storageManager.dylib)
    }
  }

  public func install_framework_file_path(_ filePath: String) async throws -> InstalledArtifact {
    return try await installBundle(URL(fileURLWithPath: filePath), intoStorage: storageManager.framework)
  }

  public func install_framework_stream(_ input: FBProcessInput<AnyObject>) async throws -> InstalledArtifact {
    return try await temporaryDirectory.withArchiveExtracted(fromStream: input, compression: .GZIP) { extractPath in
      return try await installBundle(extractPath, intoStorage: storageManager.framework)
    }
  }

  public func install_dsym_file_path(_ filePath: String, linkTo: DsymInstallLinkToBundle?) async throws -> InstalledArtifact {
    return try await installAndLinkDsym(URL(fileURLWithPath: filePath), intoStorage: storageManager.dsym, linkTo: linkTo)
  }

  public func install_dsym_stream(_ input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, linkTo: DsymInstallLinkToBundle?) async throws -> InstalledArtifact {
    return try await temporaryDirectory.withArchiveExtracted(fromStream: input, compression: compression) { extractPath in
      let url = try dsymDirnameFromUnzipDir(extractPath)
      return try await installAndLinkDsym(url, intoStorage: storageManager.dsym, linkTo: linkTo)
    }
  }

  // MARK: - Public Methods

  public func take_screenshot(_ format: FBScreenshotFormat) async throws -> Data {
    try await target.screenshot.take(format: format)
  }

  public func take_screenshot(_ configuration: ScreenshotConfiguration) async throws -> ScreenshotResult {
    try await target.screenshot.take(configuration: configuration)
  }

  public func accessibility_tap(label: String) async throws {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "tap by accessibility label", targetDescription: String(describing: target))
    }
    try await simulator.uiAutomation(backend: .accessibility).tap(.marker(value: label, key: .label, depth: .max))
  }

  public func accessibility_tap(query: FBAccessibilityElementQuery, expectedValue: String?, expectedKey: FBAXSearchableKey) async throws {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "tap by accessibility", targetDescription: String(describing: target))
    }
    let assertion = expectedValue.map { FBTapOptions.Assertion(key: expectedKey, value: $0) }
    try await simulator.uiAutomation(backend: .accessibility).tap(query, options: FBTapOptions(assertion: assertion))
  }

  /// Describes the single element `query` names, serialized in `options.format`.
  public func accessibility_describe(query: FBAccessibilityElementQuery, options: FBAccessibilityRequestOptions, backend: FBUIAutomationBackend = .accessibility) async throws -> Data {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "describe accessibility", targetDescription: String(describing: target))
    }
    return try await simulator.uiAutomation(backend: backend).describe(query, options: options)
      .formattedOutputJSON(format: options.format)
  }

  public func accessibility_scroll(query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "scroll by accessibility", targetDescription: String(describing: target))
    }
    try await simulator.uiAutomation(backend: .accessibility).scroll(query, direction: direction)
  }

  public func accessibility_set_value(query: FBAccessibilityElementQuery, value: String) async throws {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "set value by accessibility", targetDescription: String(describing: target))
    }
    try await simulator.uiAutomation(backend: .accessibility).setValue(value, for: query)
  }

  public func accessibility_drag(
    from source: FBAccessibilityElementQuery,
    to destination: FBAccessibilityElementQuery,
    options: FBDragOptions
  ) async throws {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "drag by accessibility", targetDescription: String(describing: target))
    }
    try await simulator.uiAutomation(backend: .accessibility).drag(from: source, to: destination, options: options)
  }

  public func accessibility_info_at_point(_ value: NSValue?, format: FBAccessibilityOutputFormat) async throws -> FBAccessibilityElementsResponse {
    return try await accessibility_info_at_point(
      value, options: FBAccessibilityRequestOptions(format: format, enableLogging: false))
  }

  public func accessibility_info_at_point(_ value: NSValue?, options: FBAccessibilityRequestOptions, backend: FBUIAutomationBackend = .accessibility) async throws -> FBAccessibilityElementsResponse {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "provide accessibility commands", targetDescription: String(describing: target))
    }
    let query: FBAccessibilityElementQuery = value.map { .point($0.pointValue) } ?? .frontmost
    return try await simulator.uiAutomation(backend: backend).describe(query, options: options)
  }

  // MARK: - REPL screenshot & recording

  /// The companion-host directory the target uses for per-target files. REPL
  /// screenshot/video artifacts are staged under a session subdirectory here.
  public var auxillaryDirectory: String {
    target.auxillaryDirectory
  }

  /// The frame (in screen points) of the frontmost-app accessibility element whose
  /// label contains `label` -- the same lookup as `accessibility_tap`.
  public func repl_accessibility_frame(label: String) async throws -> CGRect {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "look up an accessibility frame", targetDescription: String(describing: target))
    }
    return try await simulator.uiAutomation(backend: .accessibility)
      .frame(.marker(value: label, key: .label, depth: .max))
  }

  /// Captures a screenshot, optionally cropped to `cropRect` (in screen points),
  /// encoded as uncompressed TIFF (`asPNG == false`) or PNG.
  public func repl_screenshot(cropRect: CGRect?, asPNG: Bool) async throws -> Data {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.simulatorOnlyOperation(operation: "take a screenshot", targetDescription: String(describing: target))
    }
    return try await simulator.screenshot.takeForRepl(cropRect: cropRect, asPNG: asPNG)
  }

  /// Starts recording the target's screen to `filePath`. The returned handle's
  /// `stop()` finalizes the file. Only one recording runs at a time.
  public func repl_start_recording(toFile filePath: String) async throws -> any FBVideoRecording {
    try await target.videoRecording.startRecording(toFile: filePath)
  }

  /// Resolves when the app with `bundleID` terminates on the target. Used to drop a
  /// REPL recording that outlived the app that started it. Throws if the app's
  /// process cannot be resolved (e.g. it is not running).
  public func repl_wait_for_app_termination(bundleID: String) async throws {
    let pid = try await target.application.processID(forBundleID: bundleID)
    await waitForProcessExit(pid: pid)
  }

  public func add_media(_ filePaths: [URL]) async throws {
    try simulatorTarget().media.upload(filePaths)
  }

  public func set_location(_ latitude: Double, longitude: Double) async throws {
    try await target.location.set(longitude: longitude, latitude: latitude)
  }

  public func clear_keychain() async throws {
    try await simulatorTarget().keychain.clear()
  }

  public func approve(_ services: Set<FBTargetSettingsService>, for_application bundleID: String) async throws {
    try await simulatorTarget().privacy.grantAccess(Set([bundleID]), toServices: services)
  }

  public func revoke(_ services: Set<FBTargetSettingsService>, for_application bundleID: String) async throws {
    try await simulatorTarget().privacy.revokeAccess(Set([bundleID]), toServices: services)
  }

  public func approve_deeplink(_ scheme: String, for_application bundleID: String) async throws {
    try await simulatorTarget().privacy.grantAccess(Set([bundleID]), toDeeplink: scheme)
  }

  public func revoke_deeplink(_ scheme: String, for_application bundleID: String) async throws {
    try await simulatorTarget().privacy.revokeAccess(Set([bundleID]), toDeeplink: scheme)
  }

  public func open_url(_ url: String) async throws {
    guard let parsed = URL(string: url) else {
      throw IDBCommandError.invalidURL(urlString: url)
    }
    try await simulatorTarget().lifecycle.open(parsed)
  }

  public func focus() async throws {
    try await simulatorTarget().lifecycle.focus()
  }

  public func update_contacts(_ dbTarData: Data) async throws {
    let simulator = try simulatorTarget()
    try await temporaryDirectory.withArchiveExtracted(dbTarData) { tempDir in
      try await simulator.contacts.update(tempDir.path)
    }
  }

  public func clear_contacts() async throws {
    try await simulatorTarget().contacts.clear()
  }

  public func clear_photos() async throws {
    try await simulatorTarget().photos.clear()
  }

  public func list_test_bundles() async throws -> [XCTestDescriptor] {
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
    return try await simulatorTarget().xctest.listTests(forBundleAtPath: testDescriptor.url.path, timeout: IDBCommandExecutor.ListTestBundleTimeout, withAppAtPath: finalAppPath)
  }

  public func uninstall_application(_ bundleID: String) async throws {
    try await target.application.uninstall(bundleID: bundleID)
  }

  public func kill_application(_ bundleID: String) async throws {
    do {
      try await target.application.kill(bundleID: bundleID)
    } catch {
      // Killing an app that is not running is a no-op.
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
    return try await target.application.launch(derived)
  }

  public func crash_list(_ predicate: NSPredicate) async throws -> [CrashLogInfo] {
    return try await target.crashLog.crashes(matching: predicate, useCache: false)
  }

  public func crash_show(_ predicate: NSPredicate) async throws -> FBCrashLog {
    let crashArray = try await target.crashLog.crashes(matching: predicate, useCache: true)
    if crashArray.count > 1 {
      throw IDBCommandError.multipleCrashLogs(predicateDescription: String(describing: predicate))
    }
    guard let first = crashArray.first else {
      throw IDBCommandError.noCrashLogs(predicateDescription: String(describing: predicate))
    }
    return try first.obtainCrashLog()
  }

  public func crash_delete(_ predicate: NSPredicate) async throws -> [CrashLogInfo] {
    return try await target.crashLog.pruneCrashes(matching: predicate)
  }

  public func xctest_run(_ request: XCTestRunRequest, reporter: XCTestReporter, logger: FBControlCoreLogger) async throws -> IDBTestOperation {
    return try await request.start(withBundleStorageManager: storageManager.xctest, target: target, reporter: reporter, logger: logger, temporaryDirectory: temporaryDirectory)
  }

  /// Launches a logic test bundle in REPL mode. The implementation lives in the
  /// REPL command (`FBSimulatorReplCommands`); this forwards to the target, which
  /// injects the REPL shim (`libRepl`), forces the shim's `TestRepl/start` test,
  /// and has the shim bind a control socket whose path is passed via
  /// `IDB_REPL_SOCKET_PATH`. The returned `ReplSession.run` future completes when
  /// the test process exits, i.e. once the control socket is closed.
  public func repl_start_test(bundlePath: String) async throws -> ReplSession {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.replTestsUnsupported(targetDescription: String(describing: target))
    }
    return try await simulator.repl.startTest(bundlePath: bundlePath)
  }

  /// The product family ("iphone", "ipad", "watch", "tv", "mac", "unknown") of
  /// the target this companion is connected to. Reported to the client as part
  /// of the REPL handshake.
  public var replDeviceType: String {
    target.deviceType.family.stringRepresentation
  }

  /// The OS version ("26.2") of the target this companion is connected to.
  /// Reported to the client in the REPL handshake so it can compile injected
  /// code for the runtime's deployment target.
  public var replOSVersion: String {
    target.osVersion.versionString
  }

  /// Launches `SimulatorFrameworkBridge` on the simulator for the "simulator"
  /// REPL context. The returned `ReplSession.run` completes when the bridge
  /// process exits.
  public func repl_start_simulator() async throws -> ReplSession {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.replSessionsUnsupported(targetDescription: String(describing: target))
    }
    return try await simulator.repl.startSimulator()
  }

  /// Launches an installed app with the REPL injected, for the `app` REPL
  /// context -- or, when `reuseSession` is true, reattaches to an already-running
  /// REPL for the app. The returned `ReplSession.run` is already resolved: the app
  /// outlives the session (it resets and waits for the next client on disconnect).
  public func repl_start_app(bundleID: String, reuseSession: Bool) async throws -> ReplSession {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.replSessionsUnsupported(targetDescription: String(describing: target))
    }
    return try await simulator.repl.startApp(bundleID: bundleID, reuseSession: reuseSession)
  }

  // Keep in sync with the PRODUCT_BUNDLE_IDENTIFIER in defs.bzl
  // `make_repl_host_app` and in REPLHost/project.yml.
  static let replHostBundleID = "com.facebook.idb.replhost"

  /// Ensures the bundled ReplHost app is installed on the target and returns its
  /// bundle id. Installs it from the companion's Resources/ only if it is not
  /// already installed, so the common (already-installed) case does no filesystem
  /// work. Used by the `app` REPL context when no bundle id is given.
  public func ensureReplHostAppInstalled() async throws -> String {
    let bundleID = Self.replHostBundleID
    if (try? await target.application.installed(bundleID: bundleID)) != nil {
      return bundleID
    }
    // Not installed: locate ReplHost.app in the Resources/ directory next to the
    // companion binary (the same directory the shim dylibs load from) and install it.
    guard let appPath = BundledResources.path(forItem: "ReplHost.app") else {
      throw IDBCommandError.replHostAppMissing
    }
    _ = try await install_app_file_path(appPath, make_debuggable: false, override_modification_time: false)
    return bundleID
  }

  /// The environment that arms an app launch for the REPL (DYLD-inject libRepl +
  /// the IDB_REPL_* vars), used by `idb launch --enable-repl`. The control-socket
  /// path is deterministic, so a later `idb-repl app` reattaches. Simulator
  /// targets only.
  public func replAppLaunchEnvironment(bundleID: String) async throws -> [String: String] {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.replAppLaunchesUnsupported(targetDescription: String(describing: target))
    }
    return try await simulator.repl.appLaunchEnvironment(bundleID: bundleID)
  }

  public func debugserver_start(_ bundleID: String) async throws -> DebugServer {
    let bundle = try debugserver_prepare(bundleID)
    let server = try await target.debugger.launchDebugServer(forHostApplication: bundle, port: debugserverPort)
    debugServer = server
    return server
  }

  public func debugserver_status() throws -> DebugServer {
    guard let debugServer else {
      throw IDBCommandError.noDebugServer
    }
    return debugServer
  }

  public func debugserver_stop() async throws -> DebugServer {
    let server = try debugserver_status()
    try await server.cancel()
    debugServer = nil
    return server
  }

  public func tail_companion_logs(_ consumer: FBDataConsumer) async throws -> any LogOperation {
    return try await logger.tailToConsumer(consumer)
  }

  public func diagnostic_information() async throws -> NSDictionary {
    guard let device = target as? FBDevice else {
      return NSDictionary()
    }
    return try await device.diagnosticInformation.fetch() as NSDictionary
  }

  public func hid(_ event: FBSimulatorHIDEvent) async throws {
    let hid = try await connectToHID()
    try await event.send(on: hid)
  }

  public func set_hardware_keyboard_enabled(_ enabled: Bool) async throws {
    try await simulatorTarget().preferences.apply(.hardwareKeyboard(enabled))
  }

  public func set_preference(_ name: String, value: String, type: String?, domain: String?) async throws {
    try await simulatorTarget().preferences.apply(FBSimulatorSettingResolution(name: name, value: value, type: type, domain: domain))
  }

  public func get_preference(_ name: String, domain: String?) async throws -> String {
    try await simulatorTarget().preferences.currentSettingValue(name: name, domain: domain)
  }

  public func set_locale_with_identifier(_ identifier: String) async throws {
    try await simulatorTarget().preferences.apply(.locale(localeIdentifier: identifier))
  }

  public func get_current_locale_identifier() async throws -> String {
    try await simulatorTarget().preferences.getCurrentPreference("AppleLocale", domain: nil)
  }

  public func list_locale_identifiers() -> [String] {
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

  func push_file_from_tar(_ tarData: Data, to_path destinationPath: String, containerType: String?) async throws {
    try await temporaryDirectory.withArchiveExtracted(tarData) { extractDir in
      let paths = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
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

  public func pull_file_path(_ path: String, destination_path destinationPath: String, containerType: String?) async throws -> String {
    return try await withFileContainer(for: containerType) { container in
      try await container.copy(fromContainer: path, toHost: destinationPath)
    }
  }

  func pull_file(_ path: String, containerType: String?) async throws -> Data {
    return try await temporaryDirectory.withTemporaryDirectory { url in
      let tempPath = (url.path as NSString).appendingPathComponent((path as NSString).lastPathComponent)
      try await self.withFileContainer(for: containerType) { container in
        _ = try await container.copy(fromContainer: path, toHost: tempPath)
      }
      return try await FBArchiveOperations.createGzippedTarDataAsync(forPath: tempPath, queue: self.target.workQueue, logger: self.target.logger)
    }
  }

  public func tail(_ path: String, to_consumer consumer: FBDataConsumer, in_container containerType: String?) async throws -> FileContainerTailOperation {
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
    return try await simulatorTarget().dapServer.launch(dapPath, stdIn: stdIn, stdOut: stdOut)
  }

  public func clean() async throws {
    if target.state != .shutdown {
      try await uninstall_all_applications()
    }
    try await remove_all_storage_and_clear_keychain()
  }

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {
    try await simulatorTarget().notification.sendPush(forBundleID: bundleID, jsonPayload: jsonPayload)
  }

  public func simulateMemoryWarning() async throws {
    try await simulatorTarget().memory.simulateWarning()
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
      throw IDBCommandError.debugServerAlreadyRunning
    }
    let persisted = storageManager.application.persistedBundles
    guard let bundle = persisted[bundleID] else {
      throw IDBCommandError.notPersistedApplication(bundleID: bundleID, suitable: Array(persisted.keys))
    }
    return bundle
  }

  private func withFileContainer<R>(
    for containerType: String?,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    guard let containerType, !containerType.isEmpty else {
      if target is FBDevice {
        return try await target.file.withMediaDirectory { container in
          try await body(container)
        }
      }
      return try await target.file.withRootFilesystem { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.crashes.rawValue {
      return try await target.crashLog.withFiles { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.xctest.rawValue {
      return try await body(storageManager.xctest.asFileContainer())
    }
    if containerType == FileContainerKind.dylib.rawValue {
      return try await body(storageManager.dylib.asFileContainer())
    }
    if containerType == FileContainerKind.dsym.rawValue {
      return try await body(storageManager.dsym.asFileContainer())
    }
    if containerType == FileContainerKind.framework.rawValue {
      return try await body(storageManager.framework.asFileContainer())
    }
    if containerType == FileContainerKind.application.rawValue {
      return try await target.file.withApplicationContainers { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.group.rawValue {
      return try await target.file.withGroupContainers { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.media.rawValue {
      return try await target.file.withMediaDirectory { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.root.rawValue {
      return try await target.file.withRootFilesystem { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.provisioningProfiles.rawValue {
      return try await target.file.withProvisioningProfiles { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.mdmProfiles.rawValue {
      return try await target.file.withMDMProfiles { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.springboardIcons.rawValue {
      return try await target.file.withSpringboardIconLayout { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.wallpaper.rawValue {
      return try await target.file.withWallpaper { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.diskImages.rawValue {
      return try await target.file.withDiskImages { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.symbols.rawValue {
      return try await target.file.withSymbols { container in
        try await body(container)
      }
    }
    if containerType == FileContainerKind.auxillary.rawValue {
      return try await target.file.withAuxiliary { container in
        try await body(container)
      }
    }
    return try await target.file.withContainerApplication(containerType) { container in
      try await body(container)
    }
  }

  private func simulatorTarget() throws -> FBSimulator {
    guard let simulator = target as? FBSimulator else {
      throw IDBCommandError.notASimulator(targetDescription: String(describing: target))
    }
    return simulator
  }

  private func connectToHID() async throws -> FBSimulatorHID {
    let simulator = try simulatorTarget()
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(target.logger)
    return try await simulator.lifecycle.connectToHID()
  }

  private func installExtractedApp(_ extractPath: URL, makeDebuggable: Bool) async throws -> InstalledArtifact {
    guard let bundleDescriptor = try? FBBundleDescriptor.findAppPath(fromDirectory: extractPath, logger: target.logger) else {
      throw IDBCommandError.noAppBundleExtracted
    }
    return try await installAppBundle(bundleDescriptor, makeDebuggable: makeDebuggable)
  }

  private func installAppBundle(_ appBundle: FBBundleDescriptor, makeDebuggable: Bool) async throws -> InstalledArtifact {
    let userDevelopmentAppIsRequired = target is FBDevice
    try storageManager.application.checkArchitecture(appBundle)
    let installedApp = try await target.application.install(atPath: appBundle.path)
    // TODO: currently we have to persist it even if app is not used for debugging
    // as installed apps are referenced from xctestrun files and expanded by idb
    // by using its own application storage. Fix this by replacing xctestrun
    // placeholders by app bundle paths instead
    _ = try await storageManager.application.saveBundle(appBundle)
    if makeDebuggable && installedApp.installType != .userDevelopment && userDevelopmentAppIsRequired {
      throw IDBCommandError.userDevelopmentSigningRequired(applicationDescription: String(describing: installedApp))
    }
    return InstalledArtifact(name: appBundle.identifier, uuid: appBundle.binary?.uuid as NSUUID?, path: URL(fileURLWithPath: installedApp.bundle.path))
  }

  private func installXctest(_ extractionDirectory: URL, skipSigningBundles: Bool) async throws -> InstalledArtifact {
    return try await storageManager.xctest.saveBundleOrTestRunFromBaseDirectory(extractionDirectory, skipSigningBundles: skipSigningBundles)
  }

  private func installXctestFilePath(_ xctestURL: URL, skipSigningBundles: Bool) async throws -> InstalledArtifact {
    return try await storageManager.xctest.saveBundleOrTestRun(xctestURL, skipSigningBundles: skipSigningBundles)
  }

  private func installFile(_ extractedFile: URL, intoStorage storage: FileStorage) async throws -> InstalledArtifact {
    return try storage.saveFile(extractedFile)
  }

  private func dsymDirnameFromUnzipDir(_ parentDir: URL) throws -> URL {
    let subDirs = try FileManager.default.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
    if subDirs.count != 1 {
      return parentDir
    }
    return subDirs[0]
  }

  private func installAndLinkDsym(_ extractionDir: URL, intoStorage storage: FileStorage, linkTo: DsymInstallLinkToBundle?) async throws -> InstalledArtifact {
    let artifact = try storage.saveFileInUniquePath(extractionDir)
    guard let linkTo else {
      return artifact
    }
    let bundlePathURL: URL
    if linkTo.bundleType == .app {
      let app = try await target.application.installed(bundleID: linkTo.bundleID)
      logger.log("Going to create a symlink for app bundle: \(app.bundle.name)")
      bundlePathURL = URL(fileURLWithPath: app.bundle.path)
    } else {
      let testDescriptor = try storageManager.xctest.testDescriptor(withID: linkTo.bundleID)
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

  private func installBundle(_ extractedDirectory: URL, intoStorage storage: BundleStorage) async throws -> InstalledArtifact {
    let bundle = try StorageUtils.bundle(inDirectory: extractedDirectory)
    return try await storage.saveBundle(bundle)
  }
}
