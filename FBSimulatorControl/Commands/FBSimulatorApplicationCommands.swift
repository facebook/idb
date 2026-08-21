/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// The ways simulator application operations can fail, as data rather than assembled strings.
public enum FBSimulatorApplicationError: Error {
  case installFailed(bundleDescription: String, options: String)
  case attachmentMissingFiles(bundleID: String)
  case uninstallingSystemApplication(applicationDescription: String)
  case uninstallFailed(bundleID: String, underlying: Error)
  case servicePatternConstructionFailed
  case searchPatternConstructionFailed(bundleID: String)
  case launchingUninstalledApplication(bundleID: String, underlying: Error)
  case foregroundIfRunningIncompatibleWithWaitForDebugger
  case applicationAlreadyRunning(bundleID: String, processIdentifier: pid_t)
  case noDataDirectory(bundleID: String)
  case installInfoFieldNotAString(field: String, value: String, key: String, info: String)
  case dataContainerNotAURL(value: String, key: String, info: String)
  case applicationInfoUnavailable(path: String)
  case installingSystemApplication(applicationDescription: String)
  case applicationMissingExecutable(path: String)
  case unsupportedArchitectures(binaryArchitectures: [String], binaryPath: String, simulatorArchitectures: [String])
}

extension FBSimulatorApplicationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .installFailed(bundleDescription, options):
      return "Failed to install Application \(bundleDescription) with options \(options)"
    case let .attachmentMissingFiles(bundleID):
      return "Attaching to \(bundleID) did not yield both a stdout and a stderr file"
    case let .uninstallingSystemApplication(applicationDescription):
      return "Can't uninstall '\(applicationDescription)' as it is a system Application"
    case let .uninstallFailed(bundleID, _):
      return "Failed to uninstall '\(bundleID)'"
    case .servicePatternConstructionFailed:
      return "Couldn't build the UIKitApplication service pattern"
    case let .searchPatternConstructionFailed(bundleID):
      return "Couldn't build search pattern for '\(bundleID)'"
    case let .launchingUninstalledApplication(bundleID, underlying):
      return "App \(bundleID) can't be launched as it isn't installed: \(underlying)"
    case .foregroundIfRunningIncompatibleWithWaitForDebugger:
      return "'Foreground if running' and 'wait for debugger cannot be applied simultaneously"
    case let .applicationAlreadyRunning(bundleID, processIdentifier):
      return "App '\(bundleID)' can't be launched as it is already running (PID=\(processIdentifier))"
    case let .noDataDirectory(bundleID):
      return "Cannot launch \(bundleID) as the Simulator has no data directory"
    case let .installInfoFieldNotAString(field, value, key, info):
      return "\(field) \(value) is not a String for \(key) in \(info)"
    case let .dataContainerNotAURL(value, key, info):
      return "Data Container \(value) is not a NSURL for \(key) in \(info)"
    case let .applicationInfoUnavailable(path):
      return "Could not determine Application information for path \(path)"
    case let .installingSystemApplication(applicationDescription):
      return "Cannot install app as it is a system app \(applicationDescription)"
    case let .applicationMissingExecutable(path):
      return "Cannot install the app at \(path) as it has no executable"
    case let .unsupportedArchitectures(binaryArchitectures, binaryPath, simulatorArchitectures):
      return "Simulator does not support any of the architectures (\(FBCollectionInformation.oneLineDescription(from: binaryArchitectures))) of the executable at \(binaryPath). Simulator Archs (\(FBCollectionInformation.oneLineDescription(from: simulatorArchitectures)))"
    }
  }
}

public class FBSimulatorApplicationCommands: NSObject {

  // MARK: - Properties

  internal weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorApplicationCommands {
    return FBSimulatorApplicationCommands(simulator: simulator)
  }

  internal init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Async

  fileprivate func installApplication(withPath path: String) async throws -> FBInstalledApplication {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let appBundle = try await confirmCompatibilityOfApplication(atPath: path)
    let options: [String: Any] = ["CFBundleIdentifier": appBundle.identifier]
    let appURL = URL(fileURLWithPath: appBundle.path)
    var installError: NSError?
    do {
      try simulator.device.installApplication(appURL, withOptions: options as [AnyHashable: Any])
      return try await installedApplication(withBundleID: appBundle.identifier)
    } catch {
      installError = error as NSError
    }

    // Retry install if the first attempt failed with 'Failed to load Info.plist...'.
    if let err = installError, err.description.contains("Failed to load Info.plist from bundle at path") {
      simulator.logger.log("Retrying install due to reinstall bug")
      if (try? simulator.device.installApplication(appURL, withOptions: options as [AnyHashable: Any])) != nil {
        return try await installedApplication(withBundleID: appBundle.identifier)
      }
    }

    throw FBSimulatorApplicationError.installFailed(bundleDescription: String(describing: appBundle), options: String(describing: options))
  }

  internal func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    try await ensureApplicationIsInstalled(configuration.bundleID)
    try await confirmApplicationLaunchState(configuration.bundleID, launchMode: configuration.launchMode, waitForDebugger: configuration.waitForDebugger)
    let attachment = try await bridgeFBFuture(configuration.io.attachViaFile())
    guard let stdOut = attachment.stdOut, let stdErr = attachment.stdErr else {
      throw FBSimulatorApplicationError.attachmentMissingFiles(bundleID: configuration.bundleID)
    }
    let launch = launchApplication(configuration, stdOut: stdOut, stdErr: stdErr)
    return try await bridgeFBFuture(FBSimulatorLaunchedApplication.application(withSimulator: simulator, configuration: configuration, attachment: attachment, launchFuture: launch))
  }

  fileprivate func killApplication(withBundleID bundleID: String) async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    try simulator.device.terminateApplication(withID: bundleID)
  }

  fileprivate func installedApplications() async throws -> [FBInstalledApplication] {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let installedApps = try simulator.device.installedApps()
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

  fileprivate func uninstallApplication(withBundleID bundleID: String) async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let installedApplication = try await installedApplication(withBundleID: bundleID)
    if installedApplication.installType == .system {
      throw FBSimulatorApplicationError.uninstallingSystemApplication(applicationDescription: String(describing: installedApplication))
    }
    // Best-effort kill before uninstall; ignore errors.
    _ = try? await killApplication(withBundleID: bundleID)
    do {
      try simulator.device.uninstallApplication(bundleID, withOptions: nil)
    } catch {
      throw FBSimulatorApplicationError.uninstallFailed(bundleID: bundleID, underlying: error)
    }
  }

  fileprivate func installedApplication(withBundleID bundleID: String) async throws -> FBInstalledApplication {
    try fetchInstalledApplication(bundleID: bundleID)
  }

  fileprivate func runningApplications() async throws -> [String: NSNumber] {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let uiKitApplicationPattern = try? NSRegularExpression(pattern: "UIKitApplication:", options: []) else {
      throw FBSimulatorApplicationError.servicePatternConstructionFailed
    }
    let serviceNameToProcessIdentifier = try await simulator.serviceNamesAndProcessIdentifiers(matching: uiKitApplicationPattern)
    var mapping: [String: NSNumber] = [:]
    for serviceName in serviceNameToProcessIdentifier.keys {
      if let bundleName = FBSimulatorLaunchCtlCommands.extractApplicationBundleIdentifier(fromServiceName: serviceName) {
        mapping[bundleName] = serviceNameToProcessIdentifier[serviceName]
      }
    }
    return mapping
  }

  fileprivate func processID(withBundleID bundleID: String) async throws -> pid_t {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let pattern = "UIKitApplication:\(NSRegularExpression.escapedPattern(for: bundleID))(\\[|$)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      throw FBSimulatorApplicationError.searchPatternConstructionFailed(bundleID: bundleID)
    }
    let (_, processIdentifier) = try await simulator.firstServiceNameAndProcessIdentifier(matching: regex)
    return processIdentifier
  }

  // MARK: - Private

  private func fetchInstalledApplication(bundleID: String) throws -> FBInstalledApplication {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let device = simulator.device
    var applicationType: NSString?
    try device.applicationIsInstalled(bundleID, type: &applicationType)
    let appInfo = try device.properties(ofApplication: bundleID)
    return try FBSimulatorApplicationCommands.installedApplication(fromInfo: appInfo)
  }

  private func ensureApplicationIsInstalled(_ bundleID: String) async throws {
    do {
      _ = try await installedApplication(withBundleID: bundleID)
    } catch {
      throw FBSimulatorApplicationError.launchingUninstalledApplication(bundleID: bundleID, underlying: error)
    }
  }

  private func confirmApplicationLaunchState(_ bundleID: String, launchMode: FBApplicationLaunchMode, waitForDebugger: Bool) async throws {
    if waitForDebugger && launchMode == .foregroundIfRunning {
      throw FBSimulatorApplicationError.foregroundIfRunningIncompatibleWithWaitForDebugger
    }

    let pid: pid_t
    do {
      pid = try await processID(withBundleID: bundleID)
    } catch {
      // Process not running: treat as launchable.
      return
    }

    if launchMode == .failIfRunning {
      throw FBSimulatorApplicationError.applicationAlreadyRunning(bundleID: bundleID, processIdentifier: pid)
    } else if launchMode == .relaunchIfRunning {
      try await killApplication(withBundleID: bundleID)
    }
  }

  private func launchApplication(_ configuration: FBApplicationLaunchConfiguration, stdOut: any FBProcessFileOutput, stdErr: any FBProcessFileOutput) -> FBFuture<NSNumber> {
    fbFutureFromAsync { [self] in
      try await bridgeFBFutureVoid(stdOut.startReading())
      try await bridgeFBFutureVoid(stdErr.startReading())
      return try await launchApplication(configuration, stdOutPath: stdOut.filePath, stdErrPath: stdErr.filePath)
    }
  }

  private func launchApplication(_ configuration: FBApplicationLaunchConfiguration, stdOutPath: String?, stdErrPath: String?) async throws -> NSNumber {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let dataDirectory = simulator.dataDirectory else {
      throw FBSimulatorApplicationError.noDataDirectory(bundleID: configuration.bundleID)
    }
    let options = FBSimulatorApplicationCommands.simDeviceLaunchOptions(
      for: configuration,
      stdOutPath: translateAbsolutePath(stdOutPath, toPathRelativeTo: dataDirectory),
      stdErrPath: translateAbsolutePath(stdErrPath, toPathRelativeTo: dataDirectory))

    let logger = simulator.logger
    let bundleID = configuration.bundleID
    logger.log("Launching Application \(bundleID) with \(FBCollectionInformation.oneLineDescription(from: configuration.arguments)) \(FBCollectionInformation.oneLineDescription(from: configuration.environment))")

    let pid = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<pid_t, Error>) in
      simulator.device.launchApplicationAsync(withID: bundleID, options: options, completionQueue: simulator.workQueue) { error, pid in
        if let error {
          logger.log("Failed to launch Application \(bundleID) \(error)")
          continuation.resume(throwing: error)
        } else {
          logger.log("Launched Application \(bundleID) with pid \(pid)")
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

  // Internal (not private) so the app-launch option dictionary can be characterized by unit tests; see FBSimulatorProcessSpawnCommandsTests.
  class func simDeviceLaunchOptions(for configuration: FBApplicationLaunchConfiguration, stdOutPath: String?, stdErrPath: String?) -> [String: Any] {
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
      throw FBSimulatorApplicationError.installInfoFieldNotAString(
        field: "Bundle Name",
        value: String(describing: appInfo[FBApplicationInstallInfoKey.bundleName.rawValue] ?? "nil"),
        key: FBApplicationInstallInfoKey.bundleName.rawValue,
        info: String(describing: appInfo))
    }
    guard let _ = appInfo[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] as? String else {
      throw FBSimulatorApplicationError.installInfoFieldNotAString(
        field: "Bundle Identifier",
        value: String(describing: appInfo[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] ?? "nil"),
        key: FBApplicationInstallInfoKey.bundleIdentifier.rawValue,
        info: String(describing: appInfo))
    }
    guard let appPath = appInfo[FBApplicationInstallInfoKey.path.rawValue] as? String else {
      throw FBSimulatorApplicationError.installInfoFieldNotAString(
        field: "App Path",
        value: String(describing: appInfo[FBApplicationInstallInfoKey.path.rawValue] ?? "nil"),
        key: FBApplicationInstallInfoKey.path.rawValue,
        info: String(describing: appInfo))
    }
    guard let typeString = appInfo[FBApplicationInstallInfoKey.applicationType.rawValue] as? String else {
      throw FBSimulatorApplicationError.installInfoFieldNotAString(
        field: "Install Type",
        value: String(describing: appInfo[FBApplicationInstallInfoKey.applicationType.rawValue] ?? "nil"),
        key: FBApplicationInstallInfoKey.applicationType.rawValue,
        info: String(describing: appInfo))
    }
    let dataContainer = appInfo[keyDataContainer]
    if let dataContainer, !(dataContainer is URL) {
      throw FBSimulatorApplicationError.dataContainerNotAURL(value: String(describing: dataContainer), key: keyDataContainer, info: String(describing: appInfo))
    }

    let bundle = try FBBundleDescriptor.bundle(fromPath: appPath)

    _ = appName // used for validation only
    return FBInstalledApplication.installedApplication(
      withBundle: bundle,
      installTypeString: typeString,
      signerIdentity: nil,
      dataContainer: (dataContainer as? URL)?.path)
  }

  private func confirmCompatibilityOfApplication(atPath path: String) async throws -> FBBundleDescriptor {
    guard let application = try? FBBundleDescriptor.bundle(fromPath: path) else {
      throw FBSimulatorApplicationError.applicationInfoUnavailable(path: path)
    }
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }

    let installed: FBInstalledApplication?
    do {
      installed = try await installedApplication(withBundleID: application.identifier)
    } catch {
      installed = nil
    }
    if let installed, installed.installType == .system {
      throw FBSimulatorApplicationError.installingSystemApplication(applicationDescription: String(describing: installed))
    }
    guard let binary = application.binary else {
      throw FBSimulatorApplicationError.applicationMissingExecutable(path: path)
    }
    let binaryArchRawValues = Set(binary.architectures.map { $0.rawValue })
    let supportedArchitectures = FBiOSTargetConfiguration.baseArchsToCompatibleArch(simulator.architectures)
    let supportedArchRawValues = Set(supportedArchitectures.map { $0.rawValue })
    if binaryArchRawValues.isDisjoint(with: supportedArchRawValues) {
      throw FBSimulatorApplicationError.unsupportedArchitectures(
        binaryArchitectures: Array(binaryArchRawValues),
        binaryPath: binary.path,
        simulatorArchitectures: Array(supportedArchRawValues))
    }
    return application
  }
}

// MARK: - FBSimulator+ApplicationCommands

extension FBSimulator: ApplicationCommands {

  public func installApplication(atPath path: String) async throws -> FBInstalledApplication {
    try await applicationCommands().installApplication(withPath: path)
  }

  public func uninstallApplication(bundleID: String) async throws {
    try await applicationCommands().uninstallApplication(withBundleID: bundleID)
  }

  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    try await applicationCommands().launchApplication(configuration)
  }

  public func killApplication(bundleID: String) async throws {
    try await applicationCommands().killApplication(withBundleID: bundleID)
  }

  public func installedApplications() async throws -> [FBInstalledApplication] {
    try await applicationCommands().installedApplications()
  }

  public func installedApplication(bundleID: String) async throws -> FBInstalledApplication {
    try await applicationCommands().installedApplication(withBundleID: bundleID)
  }

  public func runningApplications() async throws -> [String: pid_t] {
    let dict = try await applicationCommands().runningApplications()
    return dict.mapValues { $0.int32Value }
  }

  public func processID(forBundleID bundleID: String) async throws -> pid_t {
    try await applicationCommands().processID(withBundleID: bundleID)
  }
}
