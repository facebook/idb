/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

public enum FBSimulatorApplicationInstallError: Error, LocalizedError {
  case installFailed(bundleDescription: String, options: String)
  case processSuspended(bundleID: String, processIdentifier: pid_t, debuggerAttached: Bool)
  case processDebuggerAttached(bundleID: String, processIdentifier: pid_t)
  case targetNotBooted(state: String)
  case targetUnavailable(reason: String)
  case installingSystemApplication(applicationDescription: String)
  case applicationMissingExecutable(path: String)
  case unsupportedArchitectures(binaryArchitectures: [String], binaryPath: String, simulatorArchitectures: [String])

  public var errorDescription: String? {
    switch self {
    case let .installFailed(bundleDescription, options):
      return "Failed to install Application \(bundleDescription) with options \(options)"
    case let .processSuspended(bundleID, processIdentifier, debuggerAttached):
      let processDescription = "Cannot install '\(bundleID)' because its existing process (PID \(processIdentifier)) is suspended."
      if debuggerAttached {
        return "\(processDescription) A debugger is attached; detach the debugger or terminate the app, then retry."
      }
      return "\(processDescription) Resume or terminate the app, then retry."
    case let .processDebuggerAttached(bundleID, processIdentifier):
      return "Cannot install '\(bundleID)' because a debugger is attached to its existing process (PID \(processIdentifier)). Detach the debugger or terminate the app, then retry."
    case let .targetNotBooted(state):
      return "Cannot install an application because the Simulator is not booted (state: \(state)). Boot it, then retry."
    case let .targetUnavailable(reason):
      return "Cannot install an application because CoreSimulator reports the target as unavailable: \(reason)"
    case let .installingSystemApplication(applicationDescription):
      return "Cannot install app as it is a system app \(applicationDescription)"
    case let .applicationMissingExecutable(path):
      return "Cannot install the app at \(path) as it has no executable"
    case let .unsupportedArchitectures(binaryArchitectures, binaryPath, simulatorArchitectures):
      return "Simulator does not support any of the architectures (\(FBCollectionInformation.oneLineDescription(from: binaryArchitectures))) of the executable at \(binaryPath). Simulator Archs (\(FBCollectionInformation.oneLineDescription(from: simulatorArchitectures)))"
    }
  }
}

public enum FBSimulatorApplicationUninstallError: Error, LocalizedError {
  case uninstallingSystemApplication(applicationDescription: String)
  case uninstallFailed(bundleID: String, underlying: Error)

  public var errorDescription: String? {
    switch self {
    case let .uninstallingSystemApplication(applicationDescription):
      return "Can't uninstall '\(applicationDescription)' as it is a system Application"
    case let .uninstallFailed(bundleID, _):
      return "Failed to uninstall '\(bundleID)'"
    }
  }
}

public enum SimulatorApplicationLaunchError: Error, LocalizedError {
  case attachmentMissingFiles(bundleID: String)
  case launchingUninstalledApplication(bundleID: String, underlying: Error)
  case foregroundIfRunningIncompatibleWithWaitForDebugger
  case applicationAlreadyRunning(bundleID: String, processIdentifier: pid_t)
  case noDataDirectory(bundleID: String)

  public var errorDescription: String? {
    switch self {
    case let .attachmentMissingFiles(bundleID):
      return "Attaching to \(bundleID) did not yield both a stdout and a stderr file"
    case let .launchingUninstalledApplication(bundleID, underlying):
      return "App \(bundleID) can't be launched as it isn't installed: \(underlying)"
    case .foregroundIfRunningIncompatibleWithWaitForDebugger:
      return "'Foreground if running' and 'wait for debugger cannot be applied simultaneously"
    case let .applicationAlreadyRunning(bundleID, processIdentifier):
      return "App '\(bundleID)' can't be launched as it is already running (PID=\(processIdentifier))"
    case let .noDataDirectory(bundleID):
      return "Cannot launch \(bundleID) as the Simulator has no data directory"
    }
  }
}

public enum SimulatorApplicationLookupError: Error, LocalizedError {
  case servicePatternConstructionFailed
  case searchPatternConstructionFailed(bundleID: String)
  case installInfoFieldNotAString(field: String, value: String, key: String, info: String)
  case dataContainerNotAURL(value: String, key: String, info: String)
  case applicationInfoUnavailable(path: String)

  public var errorDescription: String? {
    switch self {
    case .servicePatternConstructionFailed:
      return "Couldn't build the UIKitApplication service pattern"
    case let .searchPatternConstructionFailed(bundleID):
      return "Couldn't build search pattern for '\(bundleID)'"
    case let .installInfoFieldNotAString(field, value, key, info):
      return "\(field) \(value) is not a String for \(key) in \(info)"
    case let .dataContainerNotAURL(value, key, info):
      return "Data Container \(value) is not a NSURL for \(key) in \(info)"
    case let .applicationInfoUnavailable(path):
      return "Could not determine Application information for path \(path)"
    }
  }
}

enum SimulatorApplicationInstallAttempt {
  case initial
  case retry
}

public struct FBSimulatorApplicationCommands: ApplicationCommands {

  internal let simulator: FBSimulator

  // MARK: - Initializers

  public static func commands(with simulator: FBSimulator) -> FBSimulatorApplicationCommands {
    return FBSimulatorApplicationCommands(simulator: simulator)
  }

  // MARK: - Async

  public func installApplication(atPath path: String) async throws -> FBInstalledApplication {
    try confirmApplicationInstallTargetIsReady()
    let appBundle = try await confirmCompatibilityOfApplication(atPath: path)
    let options: [String: Any] = ["CFBundleIdentifier": appBundle.identifier]
    let appURL = URL(fileURLWithPath: appBundle.path)
    return try await Self.installAndResolveApplication(
      install: { attempt in
        try await self.confirmApplicationInstallPreconditions(bundleID: appBundle.identifier)
        if attempt == .retry {
          simulator.logger.log("Retrying install due to reinstall bug")
        }
        try Task.checkCancellation()
        try simulator.device.installApplication(appURL, withOptions: options as [AnyHashable: Any])
      },
      resolveInstalledApplication: { try await self.installedApplication(bundleID: appBundle.identifier) },
      installFailure: {
        .installFailed(bundleDescription: String(describing: appBundle), options: String(describing: options))
      })
  }

  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    try await ensureApplicationIsInstalled(configuration.bundleID)
    try await confirmApplicationLaunchState(configuration.bundleID, launchMode: configuration.launchMode, waitForDebugger: configuration.waitForDebugger)
    let attachment = try await bridgeFBFuture(configuration.io.attachViaFile())
    guard let stdOut = attachment.stdOut, let stdErr = attachment.stdErr else {
      throw SimulatorApplicationLaunchError.attachmentMissingFiles(bundleID: configuration.bundleID)
    }
    let launch = launchApplication(configuration, stdOut: stdOut, stdErr: stdErr)
    return try await bridgeFBFuture(SimulatorLaunchedApplication.application(withSimulator: simulator, configuration: configuration, attachment: attachment, launchFuture: launch))
  }

  public func killApplication(bundleID: String) async throws {
    try simulator.device.terminateApplication(withID: bundleID)
  }

  public func installedApplications() async throws -> [FBInstalledApplication] {
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

  public func uninstallApplication(bundleID: String) async throws {
    let installedApplication = try await installedApplication(bundleID: bundleID)
    if installedApplication.installType == .system {
      throw FBSimulatorApplicationUninstallError.uninstallingSystemApplication(applicationDescription: String(describing: installedApplication))
    }
    _ = try? await killApplication(bundleID: bundleID)
    do {
      try simulator.device.uninstallApplication(bundleID, withOptions: nil)
    } catch {
      throw FBSimulatorApplicationUninstallError.uninstallFailed(bundleID: bundleID, underlying: error)
    }
  }

  public func installedApplication(bundleID: String) async throws -> FBInstalledApplication {
    try fetchInstalledApplication(bundleID: bundleID)
  }

  public func runningApplications() async throws -> [String: pid_t] {
    guard let uiKitApplicationPattern = try? NSRegularExpression(pattern: "UIKitApplication:", options: []) else {
      throw SimulatorApplicationLookupError.servicePatternConstructionFailed
    }
    let serviceNameToProcessIdentifier = try await simulator.launchCtl.serviceNamesAndProcessIdentifiers(matching: uiKitApplicationPattern)
    var mapping: [String: pid_t] = [:]
    for (serviceName, processIdentifier) in serviceNameToProcessIdentifier {
      if let bundleName = SimulatorLaunchCtlCommands.extractApplicationBundleIdentifier(fromServiceName: serviceName) {
        mapping[bundleName] = processIdentifier.int32Value
      }
    }
    return mapping
  }

  public func processID(forBundleID bundleID: String) async throws -> pid_t {
    let pattern = "UIKitApplication:\(NSRegularExpression.escapedPattern(for: bundleID))(\\[|$)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      throw SimulatorApplicationLookupError.searchPatternConstructionFailed(bundleID: bundleID)
    }
    let (_, processIdentifier) = try await simulator.launchCtl.firstServiceNameAndProcessIdentifier(matching: regex)
    return processIdentifier
  }

  // MARK: - Private

  private func fetchInstalledApplication(bundleID: String) throws -> FBInstalledApplication {
    let device = simulator.device
    var applicationType: NSString?
    try device.applicationIsInstalled(bundleID, type: &applicationType)
    let appInfo = try device.properties(ofApplication: bundleID)
    return try FBSimulatorApplicationCommands.installedApplication(fromInfo: appInfo)
  }

  // MARK: - Install Helpers

  static func installAndResolveApplication<T>(
    install: (SimulatorApplicationInstallAttempt) async throws -> Void,
    resolveInstalledApplication: () async throws -> T,
    installFailure: () -> FBSimulatorApplicationInstallError
  ) async throws -> T {
    do {
      try await install(.initial)
      try Task.checkCancellation()
      let installedApplication = try await resolveInstalledApplication()
      try Task.checkCancellation()
      return installedApplication
    } catch let error as CancellationError {
      throw error
    } catch let error as FBSimulatorApplicationInstallError {
      try Task.checkCancellation()
      switch error {
      case .processSuspended,
        .processDebuggerAttached,
        .targetNotBooted,
        .targetUnavailable:
        throw error
      default:
        throw installFailure()
      }
    } catch {
      try Task.checkCancellation()
      guard (error as NSError).description.contains("Failed to load Info.plist from bundle at path") else {
        throw installFailure()
      }
    }

    do {
      try await install(.retry)
      try Task.checkCancellation()
    } catch let error as CancellationError {
      throw error
    } catch let error as FBSimulatorApplicationInstallError {
      try Task.checkCancellation()
      switch error {
      case .processSuspended,
        .processDebuggerAttached,
        .targetNotBooted,
        .targetUnavailable:
        throw error
      default:
        throw installFailure()
      }
    } catch {
      try Task.checkCancellation()
      throw installFailure()
    }
    let installedApplication = try await resolveInstalledApplication()
    try Task.checkCancellation()
    return installedApplication
  }

  private func confirmApplicationInstallPreconditions(bundleID: String) async throws {
    try confirmApplicationInstallTargetIsReady()
    let processFetcher = FBProcessFetcher()
    try await Self.confirmApplicationProcessIsInstallable(
      bundleID: bundleID,
      resolveProcessIdentifier: { try await self.processID(forBundleID: bundleID) },
      processIsSuspended: { (try? processFetcher.isProcessStopped($0)) != nil },
      debuggerIsAttached: { (try? processFetcher.isDebuggerAttached(to: $0)) != nil })
  }

  private func confirmApplicationInstallTargetIsReady() throws {
    let state = simulator.state
    try Self.confirmApplicationInstallTargetIsReady(
      state: state,
      stateDescription: state.stateString.rawValue,
      checkAvailability: { try simulator.device.isAvailable() })
  }

  static func confirmApplicationInstallTargetIsReady(
    state: FBiOSTargetState,
    stateDescription: String,
    checkAvailability: () throws -> Void
  ) throws {
    guard state == .booted else {
      throw FBSimulatorApplicationInstallError.targetNotBooted(state: stateDescription)
    }
    do {
      try checkAvailability()
    } catch {
      throw FBSimulatorApplicationInstallError.targetUnavailable(reason: error.localizedDescription)
    }
  }

  static func confirmApplicationProcessIsInstallable(
    bundleID: String,
    resolveProcessIdentifier: () async throws -> pid_t,
    processIsSuspended: (pid_t) -> Bool,
    debuggerIsAttached: (pid_t) -> Bool
  ) async throws {
    let processIdentifier: pid_t
    do {
      processIdentifier = try await resolveProcessIdentifier()
    } catch let error as CancellationError {
      throw error
    } catch {
      return
    }

    // Process inspection is advisory: FBProcessFetcher imports false and inspection failures as
    // throws, so either result fails open rather than blocking an otherwise valid install.
    let processSuspended = processIsSuspended(processIdentifier)
    let debuggerAttached = debuggerIsAttached(processIdentifier)
    if processSuspended {
      throw FBSimulatorApplicationInstallError.processSuspended(
        bundleID: bundleID,
        processIdentifier: processIdentifier,
        debuggerAttached: debuggerAttached)
    }
    if debuggerAttached {
      throw FBSimulatorApplicationInstallError.processDebuggerAttached(
        bundleID: bundleID,
        processIdentifier: processIdentifier)
    }
  }

  // MARK: - Private

  private func ensureApplicationIsInstalled(_ bundleID: String) async throws {
    do {
      _ = try await installedApplication(bundleID: bundleID)
    } catch {
      throw SimulatorApplicationLaunchError.launchingUninstalledApplication(bundleID: bundleID, underlying: error)
    }
  }

  private func confirmApplicationLaunchState(_ bundleID: String, launchMode: FBApplicationLaunchMode, waitForDebugger: Bool) async throws {
    if waitForDebugger && launchMode == .foregroundIfRunning {
      throw SimulatorApplicationLaunchError.foregroundIfRunningIncompatibleWithWaitForDebugger
    }

    let pid: pid_t
    do {
      pid = try await processID(forBundleID: bundleID)
    } catch {
      // Process not running: treat as launchable.
      return
    }

    if launchMode == .failIfRunning {
      throw SimulatorApplicationLaunchError.applicationAlreadyRunning(bundleID: bundleID, processIdentifier: pid)
    } else if launchMode == .relaunchIfRunning {
      try await killApplication(bundleID: bundleID)
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
    guard let dataDirectory = simulator.dataDirectory else {
      throw SimulatorApplicationLaunchError.noDataDirectory(bundleID: configuration.bundleID)
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

  static func simDeviceLaunchOptions(for configuration: FBApplicationLaunchConfiguration, stdOutPath: String?, stdErrPath: String?) -> [String: Any] {
    var options = SimulatorProcessSpawnCommands.launchOptions(
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

  private static func installedApplication(fromInfo appInfo: [String: Any]) throws -> FBInstalledApplication {
    guard let appName = appInfo[FBApplicationInstallInfoKey.bundleName.rawValue] as? String else {
      throw SimulatorApplicationLookupError.installInfoFieldNotAString(
        field: "Bundle Name",
        value: String(describing: appInfo[FBApplicationInstallInfoKey.bundleName.rawValue] ?? "nil"),
        key: FBApplicationInstallInfoKey.bundleName.rawValue,
        info: String(describing: appInfo))
    }
    guard let _ = appInfo[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] as? String else {
      throw SimulatorApplicationLookupError.installInfoFieldNotAString(
        field: "Bundle Identifier",
        value: String(describing: appInfo[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] ?? "nil"),
        key: FBApplicationInstallInfoKey.bundleIdentifier.rawValue,
        info: String(describing: appInfo))
    }
    guard let appPath = appInfo[FBApplicationInstallInfoKey.path.rawValue] as? String else {
      throw SimulatorApplicationLookupError.installInfoFieldNotAString(
        field: "App Path",
        value: String(describing: appInfo[FBApplicationInstallInfoKey.path.rawValue] ?? "nil"),
        key: FBApplicationInstallInfoKey.path.rawValue,
        info: String(describing: appInfo))
    }
    guard let typeString = appInfo[FBApplicationInstallInfoKey.applicationType.rawValue] as? String else {
      throw SimulatorApplicationLookupError.installInfoFieldNotAString(
        field: "Install Type",
        value: String(describing: appInfo[FBApplicationInstallInfoKey.applicationType.rawValue] ?? "nil"),
        key: FBApplicationInstallInfoKey.applicationType.rawValue,
        info: String(describing: appInfo))
    }
    let dataContainer = appInfo[keyDataContainer]
    if let dataContainer, !(dataContainer is URL) {
      throw SimulatorApplicationLookupError.dataContainerNotAURL(value: String(describing: dataContainer), key: keyDataContainer, info: String(describing: appInfo))
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
      throw SimulatorApplicationLookupError.applicationInfoUnavailable(path: path)
    }

    let installed: FBInstalledApplication?
    do {
      installed = try await installedApplication(bundleID: application.identifier)
    } catch {
      installed = nil
    }
    if let installed, installed.installType == .system {
      throw FBSimulatorApplicationInstallError.installingSystemApplication(applicationDescription: String(describing: installed))
    }
    guard let binary = application.binary else {
      throw FBSimulatorApplicationInstallError.applicationMissingExecutable(path: path)
    }
    let binaryArchRawValues = Set(binary.architectures.map { $0.rawValue })
    let supportedArchitectures = FBiOSTargetConfiguration.baseArchsToCompatibleArch(simulator.architectures)
    let supportedArchRawValues = Set(supportedArchitectures.map { $0.rawValue })
    if binaryArchRawValues.isDisjoint(with: supportedArchRawValues) {
      throw FBSimulatorApplicationInstallError.unsupportedArchitectures(
        binaryArchitectures: Array(binaryArchRawValues),
        binaryPath: binary.path,
        simulatorArchitectures: Array(supportedArchRawValues))
    }
    return application
  }
}
