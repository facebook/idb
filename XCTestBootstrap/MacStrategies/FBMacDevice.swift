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

/// The ways Mac-device operations can fail, as data rather than assembled strings.
public enum FBMacDeviceError: Error {
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

extension FBMacDeviceError: LocalizedError {
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
      return "Expected an FBXCTestReporter, got \(reporterDescription)"
    case let .notImplemented(selector):
      return "-[FBMacDevice \(selector)] is not implemented"
    case let .commandUnsupported(command):
      return "\(command) is not supported on the mac target"
    }
  }
}

public final class FBMacDevice: NSObject, FBiOSTarget {

  // MARK: - FBiOSTarget synthesized properties

  public let architectures: [FBArchitecture]
  public let asyncQueue: DispatchQueue
  public let auxillaryDirectory: String
  public var name: String
  public var logger: any FBControlCoreLogger
  public let osVersion: FBOSVersion
  public var state: FBiOSTargetState
  public let targetType: FBiOSTargetType
  public let workQueue: DispatchQueue
  public let screenInfo: FBiOSTargetScreenInfo?
  public var deviceType: FBDeviceType = FBDeviceType.generic(withName: "Mac")
  public let udid: String
  public let temporaryDirectory: FBTemporaryDirectory

  // MARK: - Private properties

  private var bundleIDToProductMap: [String: FBBundleDescriptor]
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

  public static func fetchInstalledApplications() -> [String: FBBundleDescriptor] {
    var mapping: [String: FBBundleDescriptor] = [:]
    let content = try? FileManager.default.contentsOfDirectory(atPath: applicationInstallDirectory)
    for fileOrDirectory in content ?? [] {
      if (fileOrDirectory as NSString).pathExtension != "app" {
        continue
      }
      let path = (applicationInstallDirectory as NSString).appendingPathComponent(fileOrDirectory)
      if let bundle = try? FBBundleDescriptor.bundle(fromPath: path) {
        mapping[bundle.identifier] = bundle
      }
    }
    return mapping
  }

  // MARK: - Initializers

  public override init() {
    architectures = Array(FBArchitectureProcessAdapter.hostMachineSupportedArchitectures())
    asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let explicitTmpDirectory = ProcessInfo.processInfo.environment["IDB_MAC_AUXILLIARY_DIR"]
    if let explicitTmpDirectory {
      auxillaryDirectory = ((explicitTmpDirectory as NSString).appendingPathComponent("idb-mac-aux") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    } else {
      auxillaryDirectory = ((NSTemporaryDirectory() as NSString).appendingPathComponent("idb-mac-cwd") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    }
    bundleIDToProductMap = FBMacDevice.fetchInstalledApplications()
    bundleIDToRunningTask = [:]
    udid = FBMacDevice.resolveDeviceUDID()
    state = .booted
    targetType = .localMac
    workQueue = DispatchQueue.main
    workingDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    screenInfo = nil
    osVersion = FBOSVersion.generic(withName: "mac")
    name = Host.current().localizedName ?? ""
    self.logger = FBControlCoreGlobalConfiguration.defaultLogger
    self.catalyst = false
    temporaryDirectory = FBTemporaryDirectory(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    super.init()
  }

  public convenience init(logger: FBControlCoreLogger) {
    self.init(logger: logger, catalyst: false)
  }

  public init(logger: FBControlCoreLogger, catalyst: Bool) {
    architectures = Array(FBArchitectureProcessAdapter.hostMachineSupportedArchitectures())
    asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let explicitTmpDirectory = ProcessInfo.processInfo.environment["IDB_MAC_AUXILLIARY_DIR"]
    if let explicitTmpDirectory {
      auxillaryDirectory = ((explicitTmpDirectory as NSString).appendingPathComponent("idb-mac-aux") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    } else {
      auxillaryDirectory = ((NSTemporaryDirectory() as NSString).appendingPathComponent("idb-mac-cwd") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    }
    bundleIDToProductMap = FBMacDevice.fetchInstalledApplications()
    bundleIDToRunningTask = [:]
    udid = FBMacDevice.resolveDeviceUDID()
    state = .booted
    targetType = .localMac
    workQueue = DispatchQueue.main
    workingDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    screenInfo = nil
    osVersion = FBOSVersion.generic(withName: "mac")
    name = Host.current().localizedName ?? ""
    self.logger = logger
    self.catalyst = catalyst
    temporaryDirectory = FBTemporaryDirectory(logger: logger)
    super.init()
  }

  // MARK: - Public

  public func restorePrimaryDeviceState() -> FBFuture<NSNull> {
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
      // The combined future resolves with the array of results; nothing reads the value,
      // so it is re-typed in place rather than paying a queue hop to replace it - callers
      // (including the state-restoration test) rely on already-resolved inputs resolving
      // this future synchronously.
      return FBFuture<AnyObject>.combine(queuedFutures).retyped(FBFuture<NSNull>.self)
    }
    return FBFuture(result: NSNull())
  }

  // MARK: - Paths

  public var runtimeRootDirectory: String {
    platformRootDirectory
  }

  public var platformRootDirectory: String {
    (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/MacOSX.platform")
  }

  public var xctestPath: String {
    (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("usr/bin/xctest")
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

  public func transportForTestManagerService() -> FBFutureContext<NSNumber> {
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
      return FBFutureContext(error: FBMacDeviceError.testManagerProxyNonConformant(proxyDescription: String(describing: rawProxy)))
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
      return FBFutureContext(error: error ?? proxyError ?? FBMacDeviceError.transportUnavailable)
    }
    return FBFuture(result: NSNumber(value: transport.fileDescriptor))
      .onQueue(
        workQueue,
        contextualTeardown: { _, _ -> FBFuture<NSNull> in
          transport.closeFile()
          return FBFuture(result: NSNull())
        }
      )
      .retyped(FBFutureContext<NSNumber>.self)
  }

  // MARK: - Process ID

  public func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    guard let task = bundleIDToRunningTask[bundleID] else {
      return FBFuture(error: FBMacDeviceError.applicationNotLaunched(bundleID: bundleID))
    }
    return FBFuture(result: NSNumber(value: task.processIdentifier))
  }

  // MARK: - Not supported

  public var consoleString: String {
    assertionFailure("consoleString is not yet supported")
    return ""
  }

  // MARK: - FBiOSTarget

  public func requiresBundlesToBeSigned() -> Bool {
    false
  }

  public static func commands(with target: FBiOSTarget) -> Self {
    assertionFailure("commandsWithTarget is not yet supported")
    return unsafeBitCast(NSNull(), to: Self.self)
  }

  public func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication> {
    do {
      let bundle = try FBBundleDescriptor.bundle(fromPath: path)
      bundleIDToProductMap[bundle.identifier] = bundle
      return FBFuture(result: FBInstalledApplication(bundle: bundle, installType: .unknown, dataContainer: nil))
    } catch {
      return FBFuture(error: error)
    }
  }

  public func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    guard let bundle = bundleIDToProductMap[bundleID] else {
      return FBFuture(error: FBMacDeviceError.applicationNotInstalled(bundleID: bundleID))
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

  public func installedApplications() -> FBFuture<NSArray> {
    let result = NSMutableArray()
    for existingBundle in bundleIDToProductMap.values {
      do {
        let bundle = try FBBundleDescriptor.bundle(fromPath: existingBundle.path)
        result.add(FBInstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil))
      } catch {
        return FBFuture(error: error)
      }
    }
    return FBFuture(result: result)
  }

  public func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication> {
    guard let existingBundle = bundleIDToProductMap[bundleID] else {
      return FBFuture(error: FBMacDeviceError.bundleNotRegistered(bundleID: bundleID))
    }
    do {
      let bundle = try FBBundleDescriptor.bundle(fromPath: existingBundle.path)
      let installedApp = FBInstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil)
      return FBFuture(result: installedApp)
    } catch {
      return FBFuture(error: error)
    }
  }

  public func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    guard let task = bundleIDToRunningTask[bundleID] else {
      return FBFuture(error: FBMacDeviceError.applicationNotLaunched(bundleID: bundleID))
    }
    task.sendSignal(SIGTERM, backingOffToKillWithTimeout: 2, logger: self.logger)
    bundleIDToRunningTask.removeValue(forKey: bundleID)
    return FBFuture(result: NSNull())
  }

  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<FBMacLaunchedApplication> {
    guard let bundle = bundleIDToProductMap[configuration.bundleID] else {
      return FBFuture(error: FBMacDeviceError.applicationNotFound(bundleID: configuration.bundleID))
    }
    guard let binary = bundle.binary else {
      return FBFuture(error: FBMacDeviceError.applicationHasNoExecutable(bundleID: bundle.identifier))
    }
    return FBProcessBuilder<AnyObject, AnyObject, AnyObject>.withLaunchPath(binary.path, arguments: configuration.arguments)
      .withEnvironment(configuration.environment)
      .start()
      .retyped(FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>.self)
      .onQueue(
        workQueue,
        map: { task in
          self.bundleIDToRunningTask[bundle.identifier] = task
          return FBMacLaunchedApplication(
            bundleID: bundle.identifier,
            processIdentifier: task.processIdentifier,
            device: self,
            queue: self.workQueue
          )
        }
      )
      .retyped(FBFuture<FBMacLaunchedApplication>.self)
  }

  public var uniqueIdentifier: String {
    udid
  }

  public var extendedInformation: [String: Any] {
    [:]
  }

  public func compare(_ target: FBiOSTarget) -> ComparisonResult {
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

  // MARK: - FBXCTestExtendedCommands

  public func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) -> FBFuture<NSArray> {
    let bundleDescriptor: FBBundleDescriptor
    do {
      bundleDescriptor = try FBBundleDescriptor.bundleWithFallbackIdentifier(fromPath: bundlePath)
    } catch {
      return FBFuture(error: error)
    }

    guard let binary = bundleDescriptor.binary else {
      return FBFuture(error: FBMacDeviceError.testBundleHasNoBinary(path: bundlePath))
    }
    let configuration = FBListTestConfiguration(
      environment: [:],
      workingDirectory: auxillaryDirectory,
      testBundlePath: bundlePath,
      runnerAppPath: appPath,
      waitForDebugger: false,
      timeout: timeout,
      architectures: Set(binary.architectures.map { $0.rawValue })
    )

    return FBListTestStrategy(target: self, configuration: configuration, logger: self.logger).listTests()
  }

  public func notifyOfCrash(_ predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    return FBCrashLogNotifier.sharedInstance.nextCrashLog(forPredicate: predicate)
  }

}

// MARK: - FBMacDevice+ProcessSpawnCommands

extension FBMacDevice: ProcessSpawnCommands {

  public func launchProcess(
    _ configuration: FBProcessSpawnConfiguration
  ) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    let logger = self.logger
    return try await bridgeFBFuture(FBSubprocess<AnyObject, AnyObject, AnyObject>.launchProcess(with: configuration, logger: logger))
  }
}

// MARK: - FBMacDevice+XCTestExtendedCommands

extension FBMacDevice: XCTestExtendedCommands {

  public func runTest(
    launchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws {
    guard let typedReporter = reporter as? FBXCTestReporter else {
      throw FBMacDeviceError.unexpectedReporter(reporterDescription: String(describing: reporter))
    }
    try await FBManagedTestRunStrategy.runToCompletion(
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
    try await FBXCTestShimConfiguration.sharedShimConfiguration().macOSTestShimPath
  }

  public func withTransportForTestManagerService<R>(
    body: (NSNumber) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(transportForTestManagerService(), body: body)
  }
}

// MARK: - FBMacDevice+ApplicationCommands

extension FBMacDevice: ApplicationCommands {

  public func installApplication(atPath path: String) async throws -> FBInstalledApplication {
    try await bridgeFBFuture(installApplication(withPath: path))
  }

  public func uninstallApplication(bundleID: String) async throws {
    try await bridgeFBFutureVoid(uninstallApplication(withBundleID: bundleID))
  }

  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    try await bridgeFBFuture(launchApplication(configuration))
  }

  public func killApplication(bundleID: String) async throws {
    try await bridgeFBFutureVoid(killApplication(withBundleID: bundleID))
  }

  public func installedApplications() async throws -> [FBInstalledApplication] {
    try await bridgeFBFutureArray(installedApplications())
  }

  public func installedApplication(bundleID: String) async throws -> FBInstalledApplication {
    try await bridgeFBFuture(installedApplication(withBundleID: bundleID))
  }

  public func runningApplications() async throws -> [String: pid_t] {
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

// MARK: - FBMacDevice+CrashLogCommands

extension FBMacDevice: CrashLogCommands {

  public func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    throw FBMacDeviceError.notImplemented(selector: "crashes:useCache:")
  }

  public func notifyOfCrash(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    try await bridgeFBFuture(notifyOfCrash(predicate))
  }

  public func pruneCrashes(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    throw FBMacDeviceError.notImplemented(selector: "pruneCrashes:")
  }

  public func withCrashLogFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw FBMacDeviceError.notImplemented(selector: "crashLogFiles")
  }
}
