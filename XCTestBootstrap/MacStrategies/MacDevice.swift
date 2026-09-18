/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import IOKit

@objc private protocol XCTestManager_XPCControl {
  func _XCT_requestConnectedSocketForTransport(_ arg1: @escaping (FileHandle?, Error?) -> Void)
}

enum MacDeviceError: Error {
  case testManagerProxyNonConformant(proxyDescription: String)
  case transportUnavailable
  case applicationNotLaunched(bundleID: String)
  case applicationNotInstalled(bundleID: String)
  case bundleNotRegistered(bundleID: String)
  case applicationNotFound(bundleID: String)
  case applicationHasNoExecutable(bundleID: String)
  case testBundleHasNoBinary(path: String)
  case unexpectedReporter(reporterDescription: String)
  case notImplemented(selector: String)
  case commandUnsupported(command: String)
}

extension MacDeviceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .testManagerProxyNonConformant(proxyDescription):
      return "The testmanagerd proxy \(proxyDescription) does not conform to XCTestManager_XPCControl"
    case .transportUnavailable:
      return "Unknown error getting transport"
    case let .applicationNotLaunched(bundleID):
      return "Application with bundleID (\(bundleID)) was not launched by XCTestBootstrap"
    case let .applicationNotInstalled(bundleID):
      return "Application with bundleID (\(bundleID)) was not installed by XCTestBootstrap"
    case let .bundleNotRegistered(bundleID):
      return "No bundle for \(bundleID)"
    case let .applicationNotFound(bundleID):
      return "Could not find application for \(bundleID)"
    case let .applicationHasNoExecutable(bundleID):
      return "Application bundle \(bundleID) has no executable"
    case let .testBundleHasNoBinary(path):
      return "Test bundle at \(path) has no binary to read architectures from"
    case let .unexpectedReporter(reporterDescription):
      return "Expected an XCTestReporter, got \(reporterDescription)"
    case let .notImplemented(selector):
      return "-[MacDevice \(selector)] is not implemented"
    case let .commandUnsupported(command):
      return "\(command) is not supported on the mac target"
    }
  }
}

public final class MacDevice: NSObject, Target {

  // MARK: - Target synthesized properties

  public let architectures: [Architecture]
  public let asyncQueue: DispatchQueue
  public let auxillaryDirectory: String
  public var name: String
  public var logger: any ControlCoreLogger
  public let osVersion: OSVersion
  public var state: TargetState
  public let targetType: TargetType
  public let workQueue: DispatchQueue
  public let screenInfo: TargetScreenInfo?
  public var deviceType: DeviceType = DeviceType.generic(withName: "Mac")
  public let udid: String
  public let temporaryDirectory: TemporaryDirectory

  // MARK: - Private properties

  private var bundleIDToProductMap: [String: BundleDescriptor]
  private var bundleIDToRunningTask: [String: FBSubprocess<AnyObject, AnyObject, AnyObject>]
  private var connection: NSXPCConnection?
  private let workingDirectory: String
  private let catalyst: Bool

  // MARK: - Static

  private static let _applicationInstallDirectory: String = {
    let uuid = UUID().uuidString
    let parentDir = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .userDomainMask, true).last ?? NSTemporaryDirectory()
    return (parentDir as NSString).appendingPathComponent(uuid)
  }()

  public static var applicationInstallDirectory: String {
    _applicationInstallDirectory
  }

  public static func fetchInstalledApplications() -> [String: BundleDescriptor] {
    var mapping: [String: BundleDescriptor] = [:]
    let content = try? FileManager.default.contentsOfDirectory(atPath: applicationInstallDirectory)
    for fileOrDirectory in content ?? [] {
      if (fileOrDirectory as NSString).pathExtension != "app" {
        continue
      }
      let path = (applicationInstallDirectory as NSString).appendingPathComponent(fileOrDirectory)
      if let bundle = try? BundleDescriptor.bundle(fromPath: path) {
        mapping[bundle.identifier] = bundle
      }
    }
    return mapping
  }

  // MARK: - Initializers

  public override init() {
    architectures = Array(ArchitectureProcessAdapter.hostMachineSupportedArchitectures())
    asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let explicitTmpDirectory = ProcessInfo.processInfo.environment["IDB_MAC_AUXILLIARY_DIR"]
    if let explicitTmpDirectory {
      auxillaryDirectory = ((explicitTmpDirectory as NSString).appendingPathComponent("idb-mac-aux") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    } else {
      auxillaryDirectory = ((NSTemporaryDirectory() as NSString).appendingPathComponent("idb-mac-cwd") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    }
    bundleIDToProductMap = MacDevice.fetchInstalledApplications()
    bundleIDToRunningTask = [:]
    udid = MacDevice.resolveDeviceUDID()
    state = .booted
    targetType = .localMac
    workQueue = DispatchQueue.main
    workingDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    screenInfo = nil
    osVersion = OSVersion.generic(withName: "mac")
    name = Host.current().localizedName ?? ""
    self.logger = ControlCoreGlobalConfiguration.defaultLogger
    self.catalyst = false
    temporaryDirectory = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger)
    super.init()
  }

  public convenience init(logger: ControlCoreLogger) {
    self.init(logger: logger, catalyst: false)
  }

  public init(logger: ControlCoreLogger, catalyst: Bool) {
    architectures = Array(ArchitectureProcessAdapter.hostMachineSupportedArchitectures())
    asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let explicitTmpDirectory = ProcessInfo.processInfo.environment["IDB_MAC_AUXILLIARY_DIR"]
    if let explicitTmpDirectory {
      auxillaryDirectory = ((explicitTmpDirectory as NSString).appendingPathComponent("idb-mac-aux") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    } else {
      auxillaryDirectory = ((NSTemporaryDirectory() as NSString).appendingPathComponent("idb-mac-cwd") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    }
    bundleIDToProductMap = MacDevice.fetchInstalledApplications()
    bundleIDToRunningTask = [:]
    udid = MacDevice.resolveDeviceUDID()
    state = .booted
    targetType = .localMac
    workQueue = DispatchQueue.main
    workingDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    screenInfo = nil
    osVersion = OSVersion.generic(withName: "mac")
    name = Host.current().localizedName ?? ""
    self.logger = logger
    self.catalyst = catalyst
    temporaryDirectory = TemporaryDirectory(logger: logger)
    super.init()
  }

  // MARK: - Public

  func restorePrimaryDeviceState() -> FBFuture<NSNull> {
    var queuedFutures: [FBFuture<AnyObject>] = []

    var killFutures: [FBFuture<AnyObject>] = []
    for bundleID in Array(bundleIDToRunningTask.keys) {
      killFutures.append(killApplication(withBundleID: bundleID).retyped(FBFuture<AnyObject>.self))
    }
    if !killFutures.isEmpty {
      queuedFutures.append(FBFuture(race: killFutures))
    }

    var uninstallFutures: [FBFuture<AnyObject>] = []
    for bundleID in Array(bundleIDToProductMap.keys) {
      uninstallFutures.append(uninstallApplication(withBundleID: bundleID).retyped(FBFuture<AnyObject>.self))
    }
    if !uninstallFutures.isEmpty {
      queuedFutures.append(FBFuture(race: uninstallFutures))
    }

    if !queuedFutures.isEmpty {
      // Re-typed in place rather than mapped: callers rely on this resolving synchronously when the inputs are already resolved.
      return FBFuture<AnyObject>.combine(queuedFutures).retyped(FBFuture<NSNull>.self)
    }
    return FBFuture(result: NSNull())
  }

  // MARK: - Paths

  public var runtimeRootDirectory: String {
    get async { await platformRootDirectory }
  }

  public var platformRootDirectory: String {
    get async {
      (XcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/MacOSX.platform")
    }
  }

  public var path: String {
    (XcodeConfiguration.developerDirectory as NSString).appendingPathComponent("usr/bin/xctest")
  }

  // MARK: - Device UDID

  private static func resolveDeviceUDID() -> String {
    let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard platformExpert != 0 else {
      return ""
    }
    let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
      platformExpert,
      kIOPlatformSerialNumberKey as CFString,
      kCFAllocatorDefault,
      0
    )
    IOObjectRelease(platformExpert)
    return serialNumberAsCFString?.takeRetainedValue() as? String ?? ""
  }

  // MARK: - Transport

  private func makeTransportForTestManagerService() throws -> FileHandle {
    let logger = self.logger
    let connection = NSXPCConnection(machServiceName: "com.apple.testmanagerd.control", options: [])
    let interface = NSXPCInterface(with: XCTestManager_XPCControl.self)
    connection.remoteObjectInterface = interface
    connection.interruptionHandler = { [weak self] in
      self?.connection = nil
      logger.log("Connection with test manager daemon was interrupted")
    }
    connection.invalidationHandler = { [weak self] in
      self?.connection = nil
      logger.log("Invalidated connection with test manager daemon")
    }
    connection.resume()
    var proxyError: Error?
    let rawProxy = connection.synchronousRemoteObjectProxyWithErrorHandler { [weak self] error in
      logger.log("Error occurred during synchronousRemoteObjectProxyWithErrorHandler call: \(error.localizedDescription)")
      self?.connection = nil
      proxyError = error
    }
    guard let proxy = rawProxy as? XCTestManager_XPCControl else {
      throw MacDeviceError.testManagerProxyNonConformant(proxyDescription: String(describing: rawProxy))
    }

    self.connection = connection
    var error: Error?
    var transport: FileHandle?
    proxy._XCT_requestConnectedSocketForTransport { file, xctError in
      if file == nil {
        logger.log("Error requesting connection with test manager daemon: \(xctError?.localizedDescription ?? "")")
        error = xctError
        return
      }
      transport = file
    }
    guard let transport else {
      throw error ?? proxyError ?? MacDeviceError.transportUnavailable
    }
    return transport
  }

  public func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    guard let task = bundleIDToRunningTask[bundleID] else {
      return FBFuture(error: MacDeviceError.applicationNotLaunched(bundleID: bundleID))
    }
    return FBFuture(result: NSNumber(value: task.processIdentifier))
  }

  var consoleString: String {
    assertionFailure("consoleString is not yet supported")
    return ""
  }

  // MARK: - Target

  public func requiresBundlesToBeSigned() -> Bool {
    false
  }

  public static func commands(with target: any Target) -> Self {
    assertionFailure("commandsWithTarget is not yet supported")
    return unsafeBitCast(NSNull(), to: Self.self)
  }

  public func installApplication(withPath path: String) throws -> InstalledApplication {
    let bundle = try BundleDescriptor.bundle(fromPath: path)
    bundleIDToProductMap[bundle.identifier] = bundle
    return InstalledApplication(bundle: bundle, installType: .unknown, dataContainer: nil)
  }

  public func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    guard let bundle = bundleIDToProductMap[bundleID] else {
      return FBFuture(error: MacDeviceError.applicationNotInstalled(bundleID: bundleID))
    }

    if !FileManager.default.fileExists(atPath: bundle.path) {
      return FBFuture(result: NSNull())
    }

    do {
      try FileManager.default.removeItem(atPath: bundle.path)
    } catch {
      return FBFuture(error: error)
    }
    bundleIDToProductMap.removeValue(forKey: bundleID)
    return FBFuture(result: NSNull())
  }

  public func installedApplication(withBundleID bundleID: String) throws -> InstalledApplication {
    guard let existingBundle = bundleIDToProductMap[bundleID] else {
      throw MacDeviceError.bundleNotRegistered(bundleID: bundleID)
    }
    let bundle = try BundleDescriptor.bundle(fromPath: existingBundle.path)
    return InstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil)
  }

  public func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    guard let task = bundleIDToRunningTask[bundleID] else {
      return FBFuture(error: MacDeviceError.applicationNotLaunched(bundleID: bundleID))
    }
    task.sendSignal(SIGTERM, backingOffToKillWithTimeout: 2, logger: self.logger)
    bundleIDToRunningTask.removeValue(forKey: bundleID)
    return FBFuture(result: NSNull())
  }

  public func launchApplication(_ configuration: ApplicationLaunchConfiguration) -> FBFuture<MacLaunchedApplication> {
    guard let bundle = bundleIDToProductMap[configuration.bundleID] else {
      return FBFuture(error: MacDeviceError.applicationNotFound(bundleID: configuration.bundleID))
    }
    guard let binary = bundle.binary else {
      return FBFuture(error: MacDeviceError.applicationHasNoExecutable(bundleID: bundle.identifier))
    }
    return FBProcessBuilder<AnyObject, AnyObject, AnyObject>.withLaunchPath(binary.path, arguments: configuration.arguments)
      .withEnvironment(configuration.environment)
      .start()
      .retyped(FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>.self)
      .onQueue(
        workQueue,
        map: { task in
          self.bundleIDToRunningTask[bundle.identifier] = task
          return MacLaunchedApplication(
            bundleID: bundle.identifier,
            processIdentifier: task.processIdentifier,
            device: self,
            queue: self.workQueue
          )
        }
      )
      .retyped(FBFuture<MacLaunchedApplication>.self)
  }

  public var uniqueIdentifier: String {
    udid
  }

  public var extendedInformation: [String: Any] {
    [:]
  }

  public func compare(_ target: any TargetInfo) -> ComparisonResult {
    .orderedSame
  }

  public var customDeviceSetPath: String? {
    nil
  }

  public func replacementMapping() -> [String: String] {
    [:]
  }

  public func environmentAdditions() -> [String: String] {
    if catalyst {
      return ["DYLD_FORCE_PLATFORM": "6"]
    } else {
      return [:]
    }
  }

  // MARK: - XCTestExtendedCommands

  public func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) -> FBFuture<NSArray> {
    let bundleDescriptor: BundleDescriptor
    do {
      bundleDescriptor = try BundleDescriptor.bundleWithFallbackIdentifier(fromPath: bundlePath)
    } catch {
      return FBFuture(error: error)
    }

    guard let binary = bundleDescriptor.binary else {
      return FBFuture(error: MacDeviceError.testBundleHasNoBinary(path: bundlePath))
    }
    let configuration = ListTestConfiguration(
      environment: [:],
      workingDirectory: auxillaryDirectory,
      testBundlePath: bundlePath,
      runnerAppPath: appPath,
      waitForDebugger: false,
      timeout: timeout,
      architectures: Set(binary.architectures.map { $0.rawValue })
    )

    return ListTestStrategy(target: self, configuration: configuration, logger: self.logger).listTests()
  }

}

// MARK: - MacDevice+ProcessSpawn

extension MacDevice {

  public func spawn(
    _ configuration: ProcessSpawnConfiguration
  ) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    let logger = self.logger
    return try await bridgeFBFuture(FBSubprocess<AnyObject, AnyObject, AnyObject>.launchProcess(with: configuration, logger: logger))
  }
}

// MARK: - MacDevice+XCTestExtendedCommands

extension MacDevice: XCTestExtendedCommands {

  public func runTest(
    launchConfiguration: TestLaunchConfiguration,
    reporter: AnyObject,
    logger: any ControlCoreLogger
  ) async throws {
    guard let typedReporter = reporter as? XCTestReporter else {
      throw MacDeviceError.unexpectedReporter(reporterDescription: String(describing: reporter))
    }
    try await ManagedTestRunStrategy.runToCompletion(
      withTarget: self,
      configuration: launchConfiguration,
      codesign: nil,
      workingDirectory: workingDirectory,
      reporter: typedReporter,
      logger: logger
    )
  }

  public func listTests(
    forBundleAtPath bundlePath: String,
    timeout: TimeInterval,
    withAppAtPath appPath: String?
  ) async throws -> [String] {
    try await bridgeFBFutureArray(
      listTests(forBundleAtPath: bundlePath, timeout: timeout, withAppAtPath: appPath))
  }

  public func extendedTestShim() async throws -> String {
    try await XCTestShimConfiguration.sharedShimConfiguration().macOSTestShimPath
  }

  public func withTransportForTestManagerService<R>(
    body: (NSNumber) async throws -> R
  ) async throws -> R {
    let transport = try makeTransportForTestManagerService()
    defer { transport.closeFile() }
    return try await body(NSNumber(value: transport.fileDescriptor))
  }
}

// MARK: - MacDevice+ApplicationCommands

extension MacDevice: ApplicationCommands {

  public func install(atPath path: String) async throws -> InstalledApplication {
    try installApplication(withPath: path)
  }

  public func uninstall(bundleID: String) async throws {
    try await bridgeFBFutureVoid(uninstallApplication(withBundleID: bundleID))
  }

  public func launch(_ configuration: ApplicationLaunchConfiguration) async throws -> LaunchedApplication {
    try await bridgeFBFuture(launchApplication(configuration))
  }

  public func kill(bundleID: String) async throws {
    try await bridgeFBFutureVoid(killApplication(withBundleID: bundleID))
  }

  public func installed() async throws -> [InstalledApplication] {
    try bundleIDToProductMap.values.map { existingBundle in
      let bundle = try BundleDescriptor.bundle(fromPath: existingBundle.path)
      return InstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil)
    }
  }

  public func installed(bundleID: String) async throws -> InstalledApplication {
    try installedApplication(withBundleID: bundleID)
  }

  public func running() async throws -> [String: pid_t] {
    var result: [String: pid_t] = [:]
    for (bundleId, task) in bundleIDToRunningTask {
      result[bundleId] = task.processIdentifier
    }
    return result
  }

  public func processID(forBundleID bundleID: String) async throws -> pid_t {
    let n = try await bridgeFBFuture(processID(withBundleID: bundleID))
    return n.int32Value
  }
}

// MARK: - MacDevice+CrashLogCommands

extension MacDevice: CrashLogCommands {

  public func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [CrashLogInfo] {
    throw MacDeviceError.notImplemented(selector: "crashes:useCache:")
  }

  public func notifyOfCrash(matching predicate: NSPredicate) async throws -> CrashLogInfo {
    try await CrashLogNotifier.sharedInstance.nextCrashLog(forPredicate: predicate)
  }

  public func prune(matching predicate: NSPredicate) async throws -> [CrashLogInfo] {
    throw MacDeviceError.notImplemented(selector: "prune:")
  }

  public func withFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw MacDeviceError.notImplemented(selector: "crashLogFiles")
  }
}

// MacDevice has no equivalent for these simulator/device-oriented commands; each throws rather than silently no-ops.

// MARK: - Unsupported command helper

extension MacDevice {

  fileprivate func macUnsupported(_ command: String) -> any Error {
    MacDeviceError.commandUnsupported(command: command)
  }
}

// MARK: - Command nouns

// `MacDevice` implements every capability inline rather than through command types, so each noun
// resolves to the device itself. Splitting those implementations into command types is a separate
// change; the nouns can be stated regardless.
extension MacDevice {

  public var application: MacDevice { self }

  public var crashLog: MacDevice { self }

  public var debugger: MacDevice { self }

  public var file: MacDevice { self }

  public var instruments: MacDevice { self }

  public var lifecycle: MacDevice { self }

  public var location: MacDevice { self }

  public var log: MacDevice { self }

  public var power: MacDevice { self }

  public var screenshot: MacDevice { self }

  public var videoRecording: MacDevice { self }

  public var videoStream: MacDevice { self }

  public var xctest: MacDevice { self }

  public var xctraceRecord: MacDevice { self }
}

// MARK: - MacDevice+VideoStreamCommands

extension MacDevice: VideoStreamCommands {

  public func create(configuration: VideoStreamConfiguration, to consumer: any DataConsumer) async throws -> any VideoStreamOperation {
    throw macUnsupported("create")
  }
}

// MARK: - MacDevice+DebuggerCommands

extension MacDevice: DebuggerCommands {

  public func launchServer(forHostApplication application: BundleDescriptor, port: in_port_t) async throws -> any DebugServer {
    throw macUnsupported("launchServer")
  }
}

// MARK: - MacDevice+Erase

extension MacDevice {

  public func erase() async throws {
    throw macUnsupported("erase")
  }
}

// MARK: - MacDevice+FileCommands

extension MacDevice: FileCommands {

  public func withContainerApplication<R>(_ bundleID: String, body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for application container")
  }

  public func withAuxiliary<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the auxillary directory")
  }

  public func withApplicationContainers<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for application containers")
  }

  public func withGroupContainers<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for group containers")
  }

  public func withRootFilesystem<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the root filesystem")
  }

  public func withMediaDirectory<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the media directory")
  }

  public func withProvisioningProfiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for provisioning profiles")
  }

  public func withMDMProfiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for MDM profiles")
  }

  public func withSpringboardIconLayout<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the springboard icon layout")
  }

  public func withWallpaper<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the wallpaper")
  }

  public func withDiskImages<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for disk images")
  }

  public func withSymbols<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for symbols")
  }
}

// MARK: - MacDevice+LocationCommands

extension MacDevice: LocationCommands {

  public func set(longitude: Double, latitude: Double) async throws {
    throw macUnsupported("set")
  }
}

// MARK: - MacDevice+LogCommands

extension MacDevice: LogCommands {

  public func tail(arguments: [String], consumer: any DataConsumer) async throws -> any LogOperation {
    throw macUnsupported("tail")
  }
}

// MARK: - MacDevice+ScreenshotCommands

extension MacDevice: ScreenshotCommands {

  public func take(configuration: ScreenshotConfiguration) async throws -> ScreenshotResult {
    throw macUnsupported("take")
  }
}

// MARK: - MacDevice+VideoRecordingCommands

extension MacDevice: VideoRecordingCommands {

  // Module-qualified because `Target.VideoRecording` is an associated type whose witness here is
  // `MacDevice` itself, which shadows the protocol of the same name inside any `MacDevice` extension.
  public func start(toFile filePath: String) async throws -> any FBControlCore.VideoRecording {
    throw macUnsupported("start")
  }
}

// MARK: - MacDevice+XCTraceRecordCommands

extension MacDevice: XCTraceRecordCommands {

  public func start(configuration: XCTraceRecordConfiguration, logger: any ControlCoreLogger) async throws -> XCTraceRecordOperation {
    throw macUnsupported("start")
  }
}

// MARK: - MacDevice+InstrumentsCommands

extension MacDevice: InstrumentsCommands {

  public func start(configuration: InstrumentsConfiguration, logger: any ControlCoreLogger) async throws -> InstrumentsOperation {
    throw macUnsupported("start")
  }
}

// MARK: - MacDevice+LifecycleCommands

extension MacDevice: LifecycleCommands {

  public func resolveState(_ state: TargetState) async throws {
    throw macUnsupported("resolveState")
  }

  public func resolveLeavesState(_ state: TargetState) async throws {
    throw macUnsupported("resolveLeavesState")
  }
}

// MARK: - MacDevice+PowerCommands

extension MacDevice: PowerCommands {

  public func shutdown() async throws {
    throw macUnsupported("shutdown")
  }

  public func reboot() async throws {
    throw macUnsupported("reboot")
  }
}

// MARK: - MacDevice+LogicTestTarget

extension MacDevice: LogicTestTarget {}
