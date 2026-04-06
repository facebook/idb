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

@objc public final class FBMacDevice: NSObject, FBiOSTarget, FBXCTestExtendedCommands, FBProcessSpawnCommands {

  // MARK: - FBiOSTarget synthesized properties

  @objc public let architectures: [FBArchitecture]
  @objc public let asyncQueue: DispatchQueue
  @objc public let auxillaryDirectory: String
  @objc public var name: String
  @objc public var logger: (any FBControlCoreLogger)?
  @objc public let osVersion: FBOSVersion
  @objc public var state: FBiOSTargetState
  @objc public let targetType: FBiOSTargetType
  @objc public let workQueue: DispatchQueue
  @objc public let screenInfo: FBiOSTargetScreenInfo?
  @objc public var deviceType: FBDeviceType = FBDeviceType.generic(withName: "Mac")
  @objc public let udid: String
  @objc public let temporaryDirectory: FBTemporaryDirectory

  // MARK: - Private properties

  private var bundleIDToProductMap: NSMutableDictionary
  private var bundleIDToRunningTask: NSMutableDictionary
  private var connection: NSXPCConnection?
  private let workingDirectory: String
  private let catalyst: Bool

  // MARK: - Static

  private static let _applicationInstallDirectory: String = {
    let uuid = UUID().uuidString
    let parentDir = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .userDomainMask, true).last!
    return (parentDir as NSString).appendingPathComponent(uuid)
  }()

  @objc public static var applicationInstallDirectory: String {
    return _applicationInstallDirectory
  }

  @objc public static func fetchInstalledApplications() -> NSMutableDictionary {
    let mapping = NSMutableDictionary()
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

  @objc public override init() {
    architectures = Array(FBArchitectureProcessAdapter.hostMachineSupportedArchitectures())
    asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let explicitTmpDirectory = ProcessInfo.processInfo.environment["IDB_MAC_AUXILLIARY_DIR"]
    if let explicitTmpDirectory {
      auxillaryDirectory = ((explicitTmpDirectory as NSString).appendingPathComponent("idb-mac-aux") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    } else {
      auxillaryDirectory = ((NSTemporaryDirectory() as NSString).appendingPathComponent("idb-mac-cwd") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    }
    bundleIDToProductMap = FBMacDevice.fetchInstalledApplications()
    bundleIDToRunningTask = NSMutableDictionary()
    udid = FBMacDevice.resolveDeviceUDID()
    state = .booted
    targetType = .localMac
    workQueue = DispatchQueue.main
    workingDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    screenInfo = nil
    osVersion = FBOSVersion.generic(withName: "mac")
    name = Host.current().localizedName ?? ""
    self.logger = nil
    self.catalyst = false
    temporaryDirectory = FBTemporaryDirectory(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    super.init()
  }

  @objc public convenience init(logger: FBControlCoreLogger) {
    self.init(logger: logger, catalyst: false)
  }

  @objc public init(logger: FBControlCoreLogger, catalyst: Bool) {
    architectures = Array(FBArchitectureProcessAdapter.hostMachineSupportedArchitectures())
    asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let explicitTmpDirectory = ProcessInfo.processInfo.environment["IDB_MAC_AUXILLIARY_DIR"]
    if let explicitTmpDirectory {
      auxillaryDirectory = ((explicitTmpDirectory as NSString).appendingPathComponent("idb-mac-aux") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    } else {
      auxillaryDirectory = ((NSTemporaryDirectory() as NSString).appendingPathComponent("idb-mac-cwd") as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
    }
    bundleIDToProductMap = FBMacDevice.fetchInstalledApplications()
    bundleIDToRunningTask = NSMutableDictionary()
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

  @objc public func restorePrimaryDeviceState() -> FBFuture<NSNull> {
    var queuedFutures: [FBFuture<AnyObject>] = []

    var killFutures: [FBFuture<AnyObject>] = []
    for bundleID in (bundleIDToRunningTask.allKeys as! [String]) {
      killFutures.append(unsafeBitCast(killApplication(withBundleID: bundleID), to: FBFuture<AnyObject>.self))
    }
    if !killFutures.isEmpty {
      queuedFutures.append(FBFuture(race: killFutures))
    }

    var uninstallFutures: [FBFuture<AnyObject>] = []
    for bundleID in (bundleIDToProductMap.allKeys as! [String]) {
      uninstallFutures.append(unsafeBitCast(uninstallApplication(withBundleID: bundleID), to: FBFuture<AnyObject>.self))
    }
    if !uninstallFutures.isEmpty {
      queuedFutures.append(FBFuture(race: uninstallFutures))
    }

    if !queuedFutures.isEmpty {
      let sel = NSSelectorFromString("futureWithFutures:")
      let method = (FBFuture<AnyObject>.self as AnyObject).method(for: sel)!
      typealias CombineFunc = @convention(c) (AnyObject, Selector, NSArray) -> AnyObject
      let combine = unsafeBitCast(method, to: CombineFunc.self)
      return unsafeDowncast(
        combine(FBFuture<AnyObject>.self as AnyObject, sel, queuedFutures as NSArray),
        to: FBFuture<NSNull>.self
      )
    }
    return FBFuture(result: NSNull())
  }

  // MARK: - Paths

  @objc public var runtimeRootDirectory: String {
    return platformRootDirectory
  }

  @objc public var platformRootDirectory: String {
    return (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/MacOSX.platform")
  }

  @objc public var xctestPath: String {
    return (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("usr/bin/xctest")
  }

  // MARK: - Device UDID

  private static func resolveDeviceUDID() -> String {
    let platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
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

  @objc public func transportForTestManagerService() -> FBFutureContext<NSNumber> {
    let logger = self.logger
    let connection = NSXPCConnection(machServiceName: "com.apple.testmanagerd.control", options: [])
    let interface = NSXPCInterface(with: XCTestManager_XPCControl.self)
    connection.remoteObjectInterface = interface
    connection.interruptionHandler = { [weak self] in
      self?.connection = nil
      logger?.log("Connection with test manager daemon was interrupted")
    }
    connection.invalidationHandler = { [weak self] in
      self?.connection = nil
      logger?.log("Invalidated connection with test manager daemon")
    }
    connection.resume()
    var proxyError: Error?
    let proxy =
      connection.synchronousRemoteObjectProxyWithErrorHandler { [weak self] error in
        logger?.log("Error occured during synchronousRemoteObjectProxyWithErrorHandler call: \(error.localizedDescription)")
        self?.connection = nil
        proxyError = error
      } as! XCTestManager_XPCControl

    self.connection = connection
    var error: Error?
    var transport: FileHandle?
    proxy._XCT_requestConnectedSocketForTransport { file, xctError in
      if file == nil {
        logger?.log("Error requesting connection with test manager daemon: \(xctError?.localizedDescription ?? "")")
        error = xctError
        return
      }
      transport = file
    }
    guard let transport else {
      let nsError = (error ?? proxyError ?? NSError(domain: "FBMacDevice", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error getting transport"])) as NSError
      // Use ObjC runtime: FBFutureContext has no Swift-visible futureContextWithError:
      let sel = NSSelectorFromString("futureContextWithError:")
      let method = (FBFutureContext<AnyObject>.self as AnyObject).method(for: sel)!
      typealias CtxErrFunc = @convention(c) (AnyObject, Selector, NSError) -> AnyObject
      let ctxErr = unsafeBitCast(method, to: CtxErrFunc.self)
      return unsafeDowncast(
        ctxErr(FBFutureContext<AnyObject>.self as AnyObject, sel, nsError),
        to: FBFutureContext<NSNumber>.self
      )
    }
    return unsafeBitCast(
      unsafeBitCast(
        FBFuture(result: NSNumber(value: transport.fileDescriptor)),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        workQueue,
        contextualTeardown: { _, _ -> FBFuture<NSNull> in
          transport.closeFile()
          return FBFuture(result: NSNull())
        }),
      to: FBFutureContext<NSNumber>.self
    )
  }

  // MARK: - Process ID

  @objc public func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    guard let task = bundleIDToRunningTask[bundleID] as? FBSubprocess<AnyObject, AnyObject, AnyObject> else {
      let error = XCTestBootstrapError.error(forDescription: "Application with bundleID (\(bundleID)) was not launched by XCTestBootstrap")
      return FBFuture(error: error)
    }
    return FBFuture(result: NSNumber(value: task.processIdentifier))
  }

  // MARK: - Not supported

  @objc public var consoleString: String {
    assertionFailure("consoleString is not yet supported")
    return ""
  }

  // MARK: - FBiOSTarget

  @objc public func requiresBundlesToBeSigned() -> Bool {
    return false
  }

  @objc public static func commands(with target: FBiOSTarget) -> Self {
    assertionFailure("commandsWithTarget is not yet supported")
    return unsafeBitCast(NSNull(), to: Self.self)
  }

  @objc public func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication> {
    do {
      let bundle = try FBBundleDescriptor.bundle(fromPath: path)
      bundleIDToProductMap[bundle.identifier] = bundle
      return FBFuture(result: FBInstalledApplication(bundle: bundle, installType: .unknown, dataContainer: nil))
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    guard let bundle = bundleIDToProductMap[bundleID] as? FBBundleDescriptor else {
      return unsafeBitCast(
        XCTestBootstrapError.describe("Application with bundleID (\(bundleID)) was not installed by XCTestBootstrap").failFuture(),
        to: FBFuture<NSNull>.self
      )
    }

    if !FileManager.default.fileExists(atPath: bundle.path) {
      return FBFuture(result: NSNull())
    }

    do {
      try FileManager.default.removeItem(atPath: bundle.path)
    } catch {
      return FBFuture(error: error)
    }
    bundleIDToProductMap.removeObject(forKey: bundleID)
    return FBFuture(result: NSNull())
  }

  @objc public func installedApplications() -> FBFuture<NSArray> {
    let result = NSMutableArray()
    for bundleID in bundleIDToProductMap.allKeys as! [String] {
      guard let existingBundle = bundleIDToProductMap[bundleID] as? FBBundleDescriptor else { continue }
      do {
        let bundle = try FBBundleDescriptor.bundle(fromPath: existingBundle.path)
        result.add(FBInstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil))
      } catch {
        return unsafeBitCast(FBFuture<AnyObject>(error: error), to: FBFuture<NSArray>.self)
      }
    }
    return FBFuture(result: result)
  }

  @objc public func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication> {
    guard let existingBundle = bundleIDToProductMap[bundleID] as? FBBundleDescriptor else {
      return FBFuture(error: NSError(domain: "FBMacDevice", code: 0, userInfo: [NSLocalizedDescriptionKey: "No bundle for \(bundleID)"]))
    }
    do {
      let bundle = try FBBundleDescriptor.bundle(fromPath: existingBundle.path)
      let installedApp = FBInstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil)
      return FBFuture(result: installedApp)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    guard let task = bundleIDToRunningTask[bundleID] as? FBSubprocess<AnyObject, AnyObject, AnyObject> else {
      let error = XCTestBootstrapError.error(forDescription: "Application with bundleID (\(bundleID)) was not launched by XCTestBootstrap")
      return FBFuture(error: error)
    }
    task.sendSignal(SIGTERM, backingOffToKillWithTimeout: 2, logger: self.logger)
    bundleIDToRunningTask.removeObject(forKey: bundleID)
    return FBFuture(result: NSNull())
  }

  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<any FBLaunchedApplication> {
    guard let bundle = bundleIDToProductMap[configuration.bundleID] as? FBBundleDescriptor else {
      return unsafeBitCast(
        FBControlCoreError.describe("Could not find application for \(configuration.bundleID)").failFuture(),
        to: FBFuture.self
      )
    }
    return unsafeBitCast(
      unsafeBitCast(
        FBProcessBuilder<AnyObject, AnyObject, AnyObject>.withLaunchPath(bundle.binary!.path, arguments: configuration.arguments)
          .withEnvironment(configuration.environment)
          .start(),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        workQueue,
        map: { taskObj -> AnyObject in
          let task = taskObj as! FBSubprocess<AnyObject, AnyObject, AnyObject>
          self.bundleIDToRunningTask[bundle.identifier] = task
          return FBMacLaunchedApplication(
            bundleID: bundle.identifier,
            processIdentifier: task.processIdentifier,
            device: self,
            queue: self.workQueue
          )
        }),
      to: FBFuture.self
    )
  }

  @objc public func runningApplications() -> FBFuture<NSDictionary> {
    let runningProcesses = NSMutableDictionary()
    let fetcher = FBProcessFetcher()
    for bundleId in bundleIDToRunningTask.allKeys as! [String] {
      if let task = bundleIDToRunningTask[bundleId] as? FBSubprocess<AnyObject, AnyObject, AnyObject> {
        runningProcesses[bundleId] = fetcher.processInfo(for: task.processIdentifier)
      }
    }
    return FBFuture(result: runningProcesses)
  }

  @objc public func runTest(with testLaunchConfiguration: FBTestLaunchConfiguration, reporter: FBXCTestReporter, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
    return FBManagedTestRunStrategy.runToCompletion(
      withTarget: self,
      configuration: testLaunchConfiguration,
      codesign: nil,
      workingDirectory: self.workingDirectory,
      reporter: reporter,
      logger: logger
    )
  }

  @objc public var uniqueIdentifier: String {
    return udid
  }

  @objc public var extendedInformation: [String: Any] {
    return [:]
  }

  @objc public func compare(_ target: FBiOSTarget) -> ComparisonResult {
    return .orderedSame
  }

  @objc public var customDeviceSetPath: String? {
    return nil
  }

  @objc public func resolve(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    return FBiOSTargetResolveState(self, state)
  }

  @objc public func resolveLeavesState(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    return FBiOSTargetResolveLeavesState(self, state)
  }

  @objc public func replacementMapping() -> [String: String] {
    return [:]
  }

  @objc public func environmentAdditions() -> [String: String] {
    if catalyst {
      return ["DYLD_FORCE_PLATFORM": "6"]
    } else {
      return [:]
    }
  }

  // MARK: - FBXCTestExtendedCommands

  @objc public func extendedTestShim() -> FBFuture<NSString> {
    return unsafeBitCast(
      unsafeBitCast(
        FBXCTestShimConfiguration.sharedShimConfiguration(with: self.logger),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        asyncQueue,
        map: { shimConfigObj -> AnyObject in
          let shims = shimConfigObj as! FBXCTestShimConfiguration
          return shims.macOSTestShimPath as NSString
        }),
      to: FBFuture<NSString>.self
    )
  }

  @objc public func listTestsForBundle(atPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) -> FBFuture<NSArray> {
    let bundleDescriptor: FBBundleDescriptor
    do {
      bundleDescriptor = try FBBundleDescriptor.bundleWithFallbackIdentifier(fromPath: bundlePath)
    } catch {
      return unsafeBitCast(FBFuture<AnyObject>(error: error), to: FBFuture<NSArray>.self)
    }

    let configuration = FBListTestConfiguration(
      environment: [:],
      workingDirectory: auxillaryDirectory,
      testBundlePath: bundlePath,
      runnerAppPath: appPath,
      waitForDebugger: false,
      timeout: timeout,
      architectures: Set(bundleDescriptor.binary!.architectures.map { $0.rawValue })
    )

    return FBListTestStrategy(target: self, configuration: configuration, logger: self.logger!).listTests()
  }

  // MARK: - Not implemented stubs

  // Swift protocol requires exact existential return types matching ObjC `id<Protocol>` generics.
  // Use unsafeBitCast since FBFuture's ObjC generic is type-erased at runtime.

  public func createStream(with configuration: FBVideoStreamConfiguration) -> FBFuture<any FBVideoStream> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice createStreamWithConfiguration:] is not implemented").failFuture(),
      to: FBFuture.self
    )
  }

  public func startRecording(toFile filePath: String) -> FBFuture<any FBiOSTargetOperation> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice startRecordingToFile:] is not implemented").failFuture(),
      to: FBFuture.self
    )
  }

  @objc public func stopRecording() -> FBFuture<NSNull> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice stopRecording] is not implemented").failFuture(),
      to: FBFuture<NSNull>.self
    )
  }

  public func tailLog(_ arguments: [String], consumer: any FBDataConsumer) -> FBFuture<any FBLogOperation> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice tailLog:consumer:] is not implemented").failFuture(),
      to: FBFuture.self
    )
  }

  @objc public func takeScreenshot(_ format: FBScreenshotFormat) -> FBFuture<NSData> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice takeScreenshot:] is not implemented").failFuture(),
      to: FBFuture<NSData>.self
    )
  }

  @objc public func notify(ofCrash predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    return FBCrashLogNotifier.sharedInstance.nextCrashLog(forPredicate: predicate)
  }

  @objc public func crashes(_ predicate: NSPredicate, useCache: Bool) -> FBFuture<NSArray> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice crashes:useCache:] is not implemented").failFuture(),
      to: FBFuture<NSArray>.self
    )
  }

  @objc public func pruneCrashes(_ predicate: NSPredicate) -> FBFuture<NSArray> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice pruneCrashes:] is not implemented").failFuture(),
      to: FBFuture<NSArray>.self
    )
  }

  public func crashLogFiles() -> FBFutureContext<any FBFileContainerProtocol> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice crashLogFiles] is not implemented").failFutureContext(),
      to: FBFutureContext.self
    )
  }

  @objc public func startInstruments(_ configuration: FBInstrumentsConfiguration, logger: FBControlCoreLogger) -> FBFuture<FBInstrumentsOperation> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice startInstruments:logger:] is not implemented").failFuture(),
      to: FBFuture<FBInstrumentsOperation>.self
    )
  }

  @objc public func startXctraceRecord(_ configuration: FBXCTraceRecordConfiguration, logger: FBControlCoreLogger) -> FBFuture<FBXCTraceRecordOperation> {
    return unsafeBitCast(
      FBControlCoreError.describe("-[FBMacDevice startXctraceRecord:logger:] is not implemented").failFuture(),
      to: FBFuture<FBXCTraceRecordOperation>.self
    )
  }

  @objc public func launchProcess(_ configuration: FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    return FBSubprocess<AnyObject, AnyObject, AnyObject>.launchProcess(with: configuration, logger: self.logger!)
  }
}
