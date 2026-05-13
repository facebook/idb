/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

// swiftlint:disable force_cast force_unwrapping

@objc public protocol FBSimulatorApplicationCommandsProtocol: NSObjectProtocol {
  @objc(installedApplicationWithBundleID:error:)
  func installedApplication(withBundleID bundleID: String) throws -> FBInstalledApplication
}

// MARK: - FBSimulator+FBSimulatorApplicationCommandsProtocol

extension FBSimulator: FBSimulatorApplicationCommandsProtocol {

  @objc(installedApplicationWithBundleID:error:)
  public func installedApplication(withBundleID bundleID: String) throws -> FBInstalledApplication {
    return try applicationCommands().installedApplication(withBundleID: bundleID)
  }
}

@objc(FBSimulatorApplicationCommands)
public class FBSimulatorApplicationCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  internal weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> Self {
    let simulator = target as! FBSimulator
    return Self(simulator: simulator)
  }

  internal required init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBApplicationCommands (legacy FBFuture entry points)

  @objc
  public func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication> {
    fbFutureFromAsync { [self] in
      try await installApplicationAsync(withPath: path)
    }
  }

  @objc
  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<FBLaunchedApplication> {
    fbFutureFromAsync { [self] in
      try await launchApplicationAsync(configuration)
    }
  }

  @objc
  public func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await killApplicationAsync(withBundleID: bundleID)
      return NSNull()
    }
  }

  @objc
  public func installedApplications() -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await installedApplicationsAsync() as NSArray
    }
  }

  @objc
  public func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await uninstallApplicationAsync(withBundleID: bundleID)
      return NSNull()
    }
  }

  @objc
  public func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication> {
    fbFutureFromAsync { [self] in
      try await installedApplicationAsync(withBundleID: bundleID)
    }
  }

  @objc
  public func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    fbFutureFromAsync { [self] in
      let pid = try await processIDAsync(withBundleID: bundleID)
      return NSNumber(value: pid)
    }
  }

  // MARK: - FBSimulatorApplicationCommandsProtocol

  @objc
  public func installedApplication(withBundleID bundleID: String) throws -> FBInstalledApplication {
    return try fetchInstalledApplication(bundleID: bundleID)
  }

  // MARK: - Async

  fileprivate func installApplicationAsync(withPath path: String) async throws -> FBInstalledApplication {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let appBundle = try await confirmCompatibilityOfApplicationAsync(atPath: path)
    let options: [String: Any] = ["CFBundleIdentifier": appBundle.identifier]
    let appURL = URL(fileURLWithPath: appBundle.path)
    var installError: NSError?
    do {
      try simulator.device.installApplication(appURL, withOptions: options as [AnyHashable: Any])
      return try await installedApplicationAsync(withBundleID: appBundle.identifier)
    } catch {
      installError = error as NSError
    }

    // Retry install if the first attempt failed with 'Failed to load Info.plist...'.
    if let err = installError, err.description.contains("Failed to load Info.plist from bundle at path") {
      simulator.logger?.log("Retrying install due to reinstall bug")
      if (try? simulator.device.installApplication(appURL, withOptions: options as [AnyHashable: Any])) != nil {
        return try await installedApplicationAsync(withBundleID: appBundle.identifier)
      }
    }

    throw FBSimulatorError.describe("Failed to install Application \(appBundle) with options \(options)").build()
  }

  internal func launchApplicationAsync(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await ensureApplicationIsInstalledAsync(configuration.bundleID)
    try await confirmApplicationLaunchStateAsync(configuration.bundleID, launchMode: configuration.launchMode, waitForDebugger: configuration.waitForDebugger)
    let attachment = try await bridgeFBFuture(configuration.io.attachViaFile())
    let launch = launchApplication(configuration, stdOut: attachment.stdOut!, stdErr: attachment.stdErr!)
    return try await bridgeFBFuture(FBSimulatorLaunchedApplication.application(withSimulator: simulator, configuration: configuration, attachment: attachment, launchFuture: launch))
  }

  fileprivate func killApplicationAsync(withBundleID bundleID: String) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try simulator.device.terminateApplication(withID: bundleID)
  }

  fileprivate func installedApplicationsAsync() async throws -> [FBInstalledApplication] {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let installedApps = try FBSimDeviceWrapper.installedApps(onDevice: simulator.device)
    var applications: [FBInstalledApplication] = []
    for appInfo in installedApps.values {
      guard let dict = appInfo as? [String: Any],
        let application = try? FBSimulatorApplicationCommands.installedApplication(fromInfo: dict)
      else {
        continue
      }
      applications.append(application)
    }
    return applications
  }

  fileprivate func uninstallApplicationAsync(withBundleID bundleID: String) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let installedApplication = try await installedApplicationAsync(withBundleID: bundleID)
    if installedApplication.installType == .system {
      throw FBSimulatorError.describe("Can't uninstall '\(installedApplication)' as it is a system Application").build()
    }
    // Best-effort kill before uninstall; ignore errors.
    _ = try? await killApplicationAsync(withBundleID: bundleID)
    do {
      try simulator.device.uninstallApplication(bundleID, withOptions: nil)
    } catch {
      throw FBSimulatorError.describe("Failed to uninstall '\(bundleID)'").build()
    }
  }

  fileprivate func installedApplicationAsync(withBundleID bundleID: String) async throws -> FBInstalledApplication {
    return try fetchInstalledApplication(bundleID: bundleID)
  }

  fileprivate func runningApplicationsAsync() async throws -> [String: NSNumber] {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let serviceNameToProcessIdentifier = try await bridgeFBFuture(simulator.serviceNamesAndProcessIdentifiers(matching: FBSimulatorApplicationCommands.uiKitApplicationRegex)) as! [String: NSNumber]
    var mapping: [String: NSNumber] = [:]
    for serviceName in serviceNameToProcessIdentifier.keys {
      if let bundleName = FBSimulatorLaunchCtlCommands.extractApplicationBundleIdentifier(fromServiceName: serviceName) {
        mapping[bundleName] = serviceNameToProcessIdentifier[serviceName]
      }
    }
    return mapping
  }

  fileprivate func processIDAsync(withBundleID bundleID: String) async throws -> pid_t {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let pattern = "UIKitApplication:\(NSRegularExpression.escapedPattern(for: bundleID))(\\[|$)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      throw FBSimulatorError.describe("Couldn't build search pattern for '\(bundleID)'").build()
    }
    let result = try await bridgeFBFuture(simulator.firstServiceNameAndProcessIdentifier(matching: regex)) as! [Any]
    return (result[1] as! NSNumber).int32Value
  }

  // MARK: - Private

  private func fetchInstalledApplication(bundleID: String) throws -> FBInstalledApplication {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let device = simulator.device
    var applicationType: NSString?
    try device.applicationIsInstalled(bundleID, type: &applicationType)
    let appInfo = try device.properties(ofApplication: bundleID)
    return try FBSimulatorApplicationCommands.installedApplication(fromInfo: appInfo)
  }

  private static let uiKitApplicationRegex: NSRegularExpression = {
    return try! NSRegularExpression(pattern: "UIKitApplication:", options: [])
  }()

  private func ensureApplicationIsInstalledAsync(_ bundleID: String) async throws {
    do {
      _ = try await installedApplicationAsync(withBundleID: bundleID)
    } catch {
      throw FBSimulatorError.describe("App \(bundleID) can't be launched as it isn't installed: \(error)").build()
    }
  }

  private func confirmApplicationLaunchStateAsync(_ bundleID: String, launchMode: FBApplicationLaunchMode, waitForDebugger: Bool) async throws {
    if waitForDebugger && launchMode == .foregroundIfRunning {
      throw FBSimulatorError.describe("'Foreground if running' and 'wait for debugger cannot be applied simultaneously").build()
    }

    let pid: pid_t
    do {
      pid = try await processIDAsync(withBundleID: bundleID)
    } catch {
      // Process not running: treat as launchable.
      return
    }

    if launchMode == .failIfRunning {
      throw FBSimulatorError.describe("App '\(bundleID)' can't be launched as it is already running (PID=\(pid))").build()
    } else if launchMode == .relaunchIfRunning {
      try await killApplicationAsync(withBundleID: bundleID)
    }
  }

  private func launchApplication(_ configuration: FBApplicationLaunchConfiguration, stdOut: any FBProcessFileOutput, stdErr: any FBProcessFileOutput) -> FBFuture<NSNumber> {
    fbFutureFromAsync { [self] in
      try await bridgeFBFutureVoid(stdOut.startReading())
      try await bridgeFBFutureVoid(stdErr.startReading())
      return try await launchApplicationAsync(configuration, stdOutPath: stdOut.filePath, stdErrPath: stdErr.filePath)
    }
  }

  private func launchApplicationAsync(_ configuration: FBApplicationLaunchConfiguration, stdOutPath: String?, stdErrPath: String?) async throws -> NSNumber {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let options = FBSimulatorApplicationCommands.simDeviceLaunchOptions(
      for: configuration,
      stdOutPath: translateAbsolutePath(stdOutPath, toPathRelativeTo: simulator.dataDirectory!),
      stdErrPath: translateAbsolutePath(stdErrPath, toPathRelativeTo: simulator.dataDirectory!))

    let logger = simulator.logger
    logger?.log("Launching Application \(configuration.bundleID) with \(FBCollectionInformation.oneLineDescription(from: configuration.arguments)) \(FBCollectionInformation.oneLineDescription(from: configuration.environment))")

    let pid = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<pid_t, Error>) in
      simulator.device.launchApplicationAsync(withID: configuration.bundleID, options: options, completionQueue: simulator.workQueue) { error, pid in
        if let error {
          logger?.log("Failed to launch Application \(configuration.bundleID) \(error)")
          continuation.resume(throwing: error)
        } else {
          logger?.log("Launched Application \(configuration.bundleID) with pid \(pid)")
          continuation.resume(returning: pid)
        }
      }
    }
    return NSNumber(value: pid)
  }

  private func translateAbsolutePath(_ absolutePath: String?, toPathRelativeTo referencePath: String) -> String? {
    guard let absolutePath else { return nil }
    if !absolutePath.hasPrefix("/") {
      return absolutePath
    }
    var translatedPath = ""
    for _ in (referencePath as NSString).pathComponents {
      translatedPath = (translatedPath as NSString).appendingPathComponent("..")
    }
    return (translatedPath as NSString).appendingPathComponent(absolutePath)
  }

  private class func simDeviceLaunchOptions(for configuration: FBApplicationLaunchConfiguration, stdOutPath: String?, stdErrPath: String?) -> [String: Any] {
    var options = FBSimulatorProcessSpawnCommands.launchOptions(
      withArguments: configuration.arguments,
      environment: configuration.environment,
      waitForDebugger: configuration.waitForDebugger)
    if let stdOutPath {
      options["stdout"] = stdOutPath
    }
    if let stdErrPath {
      options["stderr"] = stdErrPath
    }
    return options
  }

  private static let keyDataContainer = "DataContainer"

  private class func installedApplication(fromInfo appInfo: [String: Any]) throws -> FBInstalledApplication {
    guard let appName = appInfo[FBApplicationInstallInfoKey.bundleName.rawValue] as? String else {
      throw FBControlCoreError.describe("Bundle Name \(appInfo[FBApplicationInstallInfoKey.bundleName.rawValue] ?? "nil") is not a String for \(FBApplicationInstallInfoKey.bundleName.rawValue) in \(appInfo)").build()
    }
    guard let _ = appInfo[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] as? String else {
      throw FBControlCoreError.describe("Bundle Identifier \(appInfo[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] ?? "nil") is not a String for \(FBApplicationInstallInfoKey.bundleIdentifier.rawValue) in \(appInfo)").build()
    }
    guard let appPath = appInfo[FBApplicationInstallInfoKey.path.rawValue] as? String else {
      throw FBControlCoreError.describe("App Path \(appInfo[FBApplicationInstallInfoKey.path.rawValue] ?? "nil") is not a String for \(FBApplicationInstallInfoKey.path.rawValue) in \(appInfo)").build()
    }
    guard let typeString = appInfo[FBApplicationInstallInfoKey.applicationType.rawValue] as? String else {
      throw FBControlCoreError.describe("Install Type \(appInfo[FBApplicationInstallInfoKey.applicationType.rawValue] ?? "nil") is not a String for \(FBApplicationInstallInfoKey.applicationType.rawValue) in \(appInfo)").build()
    }
    let dataContainer = appInfo[keyDataContainer]
    if let dataContainer, !(dataContainer is URL) {
      throw FBControlCoreError.describe("Data Container \(dataContainer) is not a NSURL for \(keyDataContainer) in \(appInfo)").build()
    }

    let bundle = try FBBundleDescriptor.bundle(fromPath: appPath)

    _ = appName // used for validation only
    return FBInstalledApplication.installedApplication(
      withBundle: bundle,
      installTypeString: typeString,
      signerIdentity: nil,
      dataContainer: (dataContainer as? URL)?.path)
  }

  private func confirmCompatibilityOfApplicationAsync(atPath path: String) async throws -> FBBundleDescriptor {
    guard let application = try? FBBundleDescriptor.bundle(fromPath: path) else {
      throw FBSimulatorError.describe("Could not determine Application information for path \(path)").build()
    }
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }

    let installed: FBInstalledApplication?
    do {
      installed = try await installedApplicationAsync(withBundleID: application.identifier)
    } catch {
      installed = nil
    }
    if let installed, installed.installType == .system {
      throw FBSimulatorError.describe("Cannot install app as it is a system app \(installed)").build()
    }
    let binaryArchRawValues = Set(application.binary!.architectures.map { $0.rawValue })
    let supportedArchitectures = FBiOSTargetConfiguration.baseArchsToCompatibleArch(simulator.architectures)
    let supportedArchRawValues = Set(supportedArchitectures.map { $0.rawValue })
    if binaryArchRawValues.isDisjoint(with: supportedArchRawValues) {
      throw FBSimulatorError.describe(
        "Simulator does not support any of the architectures (\(FBCollectionInformation.oneLineDescription(from: Array(binaryArchRawValues)))) of the executable at \(application.binary!.path). Simulator Archs (\(FBCollectionInformation.oneLineDescription(from: Array(supportedArchRawValues))))"
      ).build()
    }
    return application
  }
}

// MARK: - FBSimulator+AsyncApplicationCommands

extension FBSimulator: AsyncApplicationCommands {

  public func installApplication(atPath path: String) async throws -> FBInstalledApplication {
    try await applicationCommands().installApplicationAsync(withPath: path)
  }

  public func uninstallApplication(bundleID: String) async throws {
    try await applicationCommands().uninstallApplicationAsync(withBundleID: bundleID)
  }

  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    try await applicationCommands().launchApplicationAsync(configuration)
  }

  public func killApplication(bundleID: String) async throws {
    try await applicationCommands().killApplicationAsync(withBundleID: bundleID)
  }

  public func installedApplications() async throws -> [FBInstalledApplication] {
    try await applicationCommands().installedApplicationsAsync()
  }

  public func installedApplication(bundleID: String) async throws -> FBInstalledApplication {
    try await applicationCommands().installedApplicationAsync(withBundleID: bundleID)
  }

  public func runningApplications() async throws -> [String: pid_t] {
    let dict = try await applicationCommands().runningApplicationsAsync()
    return dict.mapValues { $0.int32Value }
  }

  public func processID(forBundleID bundleID: String) async throws -> pid_t {
    try await applicationCommands().processIDAsync(withBundleID: bundleID)
  }
}

// MARK: - FBSimulator+FBApplicationCommands

extension FBSimulator: FBApplicationCommands {

  @objc(installApplicationWithPath:)
  public func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication> {
    do {
      return try applicationCommands().installApplication(withPath: path)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(uninstallApplicationWithBundleID:)
  public func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    do {
      return try applicationCommands().uninstallApplication(withBundleID: bundleID)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(launchApplication:)
  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<FBLaunchedApplication> {
    do {
      return try applicationCommands().launchApplication(configuration)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(killApplicationWithBundleID:)
  public func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    do {
      return try applicationCommands().killApplication(withBundleID: bundleID)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func installedApplications() -> FBFuture<NSArray> {
    do {
      return try applicationCommands().installedApplications()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(installedApplicationWithBundleID:)
  public func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication> {
    do {
      return try applicationCommands().installedApplication(withBundleID: bundleID)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(processIDWithBundleID:)
  public func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    do {
      return try applicationCommands().processID(withBundleID: bundleID)
    } catch {
      return FBFuture(error: error)
    }
  }
}
