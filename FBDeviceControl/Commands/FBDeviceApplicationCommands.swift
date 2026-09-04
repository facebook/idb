/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// MARK: - FBDeviceApplicationError

public enum FBDeviceApplicationError: Error {
  case awaitingTerminationUnsupported
  case installFailed(applicationName: String, status: Int32, message: String, recentEvents: String)
  case uninstallFailed(bundleID: String, status: Int32, message: String, recentEvents: String)
  case applicationNotInstalled(bundleID: String, installed: [String])
  case noProcessID(bundleID: String)
  case applicationLookupFailed(status: Int32, message: String)
  case applicationLookupMalformed
  case pidListRequestFailed(underlying: Error)
  case pidListAcknowledgementFailed(underlying: Error)
  case pidListResponseFailed(underlying: Error)
  case pidListResponseNotADictionary(response: String)
  case pidListRequestUnsuccessful
  case missingBundleIdentifier(key: String, application: String)
}

extension FBDeviceApplicationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .awaitingTerminationUnsupported:
      return "Awaiting termination is not supported for device applications"
    case let .installFailed(applicationName, status, message, recentEvents):
      return "Failed to install application \(applicationName) 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(message)). \(recentEvents)"
    case let .uninstallFailed(bundleID, status, message, recentEvents):
      return "Failed to uninstall application '\(bundleID)' with error 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(message)). \(recentEvents)"
    case let .applicationNotInstalled(bundleID, installed):
      return "Application with bundle ID: \(bundleID) is not installed. Installed apps \(FBCollectionInformation.oneLineDescription(from: installed))"
    case let .noProcessID(bundleID):
      return "No pid for \(bundleID)"
    case let .applicationLookupFailed(status, message):
      return "Failed to get list of applications 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(message))"
    case .applicationLookupMalformed:
      return "Application lookup did not return a mapping of bundle identifiers to attributes"
    case let .pidListRequestFailed(underlying):
      return "Failed to request PidList \(underlying)"
    case let .pidListAcknowledgementFailed(underlying):
      return "Failed to receive 1 byte after PidList \(underlying)"
    case let .pidListResponseFailed(underlying):
      return "Failed to receive PidList response \(underlying)"
    case let .pidListResponseNotADictionary(response):
      return "PidList response \(response) is not a dictionary"
    case .pidListRequestUnsuccessful:
      return "Request to PidList is not RequestSuccessful"
    case let .missingBundleIdentifier(key, application):
      return "No \(key) in installed application \(application)"
    }
  }
}

// MARK: - FBDeviceWorkflowStatistics

private class FBDeviceWorkflowStatistics {
  let workflowType: String
  let logger: any FBControlCoreLogger
  var lastEvent: [String: Any]?

  init(workflowType: String, logger: any FBControlCoreLogger) {
    self.workflowType = workflowType
    self.logger = logger
  }

  func pushProgress(_ event: [String: Any]) {
    logger.log("\(workflowType) Progress: \(FBCollectionInformation.oneLineDescription(from: event))")
    lastEvent = event
  }

  var summaryOfRecentEvents: String {
    guard let lastEvent else {
      return "No events recorded"
    }
    return "Last event \(FBCollectionInformation.oneLineDescription(from: lastEvent))"
  }
}

private func workflowCallback(_ callbackDictionary: [String: Any]?, _ context: UnsafeMutableRawPointer?) {
  guard let context, let callbackDictionary else { return }
  let statistics = Unmanaged<FBDeviceWorkflowStatistics>.fromOpaque(context).takeUnretainedValue()
  statistics.pushProgress(callbackDictionary)
}

// MARK: - FBDeviceLaunchedApplication

private class FBDeviceLaunchedApplication: FBLaunchedApplication {
  let processIdentifier: pid_t
  private let _configuration: FBApplicationLaunchConfiguration
  private let commands: FBDeviceApplicationCommands
  private let queue: DispatchQueue

  init(processIdentifier: pid_t, configuration: FBApplicationLaunchConfiguration, commands: FBDeviceApplicationCommands, queue: DispatchQueue) {
    self.processIdentifier = processIdentifier
    self._configuration = configuration
    self.commands = commands
    self.queue = queue
  }

  func waitForTermination() async throws {
    throw FBDeviceApplicationError.awaitingTerminationUnsupported
  }

  func terminate() async throws {
    try await commands.killApplication(withProcessIdentifier: processIdentifier)
  }

  var bundleID: String {
    _configuration.bundleID
  }
}

// MARK: - FBDeviceApplicationCommands

public final class FBDeviceApplicationCommands {
  fileprivate weak var device: FBDevice?
  private let deltaUpdateDirectory: URL

  // MARK: Initializers

  public class func commands(with device: FBDevice) -> FBDeviceApplicationCommands {
    let deltaUpdateDirectory = device.temporaryDirectory.temporaryDirectory()
    return FBDeviceApplicationCommands(device: device, deltaUpdateDirectory: deltaUpdateDirectory)
  }

  init(device: FBDevice, deltaUpdateDirectory: URL) {
    self.device = device
    self.deltaUpdateDirectory = deltaUpdateDirectory
  }

  // MARK: - Async

  fileprivate func installApplication(withPath path: String) async throws -> FBInstalledApplication {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let bundle = try FBBundleDescriptor.bundle(fromPath: path)
    let appURL = URL(fileURLWithPath: path, isDirectory: true)
    let options: [String: Any] = [
      "CFBundleIdentifier": bundle.identifier,
      "CloseOnInvalidate": 1,
      "InvalidateOnDetach": 1,
      "IsUserInitiated": 1,
      "PackageType": "Developer",
      "ShadowParentKey": deltaUpdateDirectory,
    ]
    try await device.withConnectedDevice(purpose: "install") { connectedDevice in
      device.logger.log("Installing Application \(appURL)")
      let statistics = FBDeviceWorkflowStatistics(workflowType: "Install", logger: connectedDevice.logger)
      let context = Unmanaged.passUnretained(statistics).toOpaque()
      let status =
        connectedDevice.calls.SecureInstallApplicationBundle?(
          connectedDevice.amDeviceRef,
          appURL as CFURL,
          options as CFDictionary,
          workflowCallback,
          context
        ) ?? -1
      if status != 0 {
        let errorMessage = connectedDevice.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
        throw FBDeviceApplicationError.installFailed(applicationName: appURL.lastPathComponent, status: status, message: errorMessage, recentEvents: statistics.summaryOfRecentEvents)
      }
      device.logger.log("Installed Application \(appURL)")
    }
    return try await installedApplication(withBundleID: bundle.identifier)
  }

  fileprivate func uninstallApplication(withBundleID bundleID: String) async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    try await device.withConnectedDevice(purpose: "uninstall_\(bundleID)") { connectedDevice in
      let statistics = FBDeviceWorkflowStatistics(workflowType: "Uninstall", logger: connectedDevice.logger)
      device.logger.log("Uninstalling Application \(bundleID)")
      let context = Unmanaged.passUnretained(statistics).toOpaque()
      let status =
        connectedDevice.calls.SecureUninstallApplication?(
          nil,
          connectedDevice.amDeviceRef,
          bundleID as CFString,
          0,
          workflowCallback,
          context
        ) ?? -1
      if status != 0 {
        let internalMessage = connectedDevice.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
        throw FBDeviceApplicationError.uninstallFailed(bundleID: bundleID, status: status, message: internalMessage, recentEvents: statistics.summaryOfRecentEvents)
      }
      device.logger.log("Uninstalled Application \(bundleID)")
    }
  }

  fileprivate func installedApplications() async throws -> [FBInstalledApplication] {
    let applicationData = try await installedApplicationsData(Self.installedApplicationLookupAttributes)
    var installedApplications: [FBInstalledApplication] = []
    for app in applicationData.values {
      let application = try FBDeviceApplicationCommands.installedApplication(from: app)
      installedApplications.append(application)
    }
    return installedApplications
  }

  fileprivate func installedApplication(withBundleID bundleID: String) async throws -> FBInstalledApplication {
    let applicationData = try await installedApplicationsData(Self.installedApplicationLookupAttributes)
    guard let app = applicationData[bundleID] else {
      throw FBDeviceApplicationError.applicationNotInstalled(bundleID: bundleID, installed: Array(applicationData.keys))
    }
    return try FBDeviceApplicationCommands.installedApplication(from: app)
  }

  fileprivate func runningApplications() async throws -> [String: NSNumber] {
    let pidToRunningProcessName = try await pidToRunningProcessName()
    let bundleIdentifierToAttributes = try await installedApplicationsData(Self.namingLookupAttributes)
    var bundleNameToBundleIdentifier: [String: String] = [:]
    for (bundleIdentifier, attributes) in bundleIdentifierToAttributes {
      if let bundleName = attributes[FBApplicationInstallInfoKey.bundleName.rawValue] as? String {
        bundleNameToBundleIdentifier[bundleName] = bundleIdentifier
      }
    }
    var runningProcessNameToPID: [String: NSNumber] = [:]
    for (pid, processName) in pidToRunningProcessName {
      runningProcessNameToPID[processName] = pid
    }
    var bundleNameToPID: [String: NSNumber] = [:]
    for (processName, pid) in runningProcessNameToPID {
      if let bundleName = bundleNameToBundleIdentifier[processName] {
        bundleNameToPID[bundleName] = pid
      }
    }
    return bundleNameToPID
  }

  fileprivate func processID(withBundleID bundleID: String) async throws -> NSNumber {
    let running = try await runningApplications()
    guard let pid = running[bundleID] else {
      throw FBDeviceApplicationError.noProcessID(bundleID: bundleID)
    }
    return pid
  }

  fileprivate func killApplication(withBundleID bundleID: String) async throws {
    let pid = try await processID(withBundleID: bundleID)
    try await killApplication(withProcessIdentifier: pid.int32Value)
  }

  fileprivate func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> any FBLaunchedApplication {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let pid: NSNumber
    if device.osVersion.version.majorVersion >= 17 {
      let devicectl = FBAppleDevicectlCommandExecutor(device: device)
      pid = try await devicectl.launchApplication(configuration: configuration)
    } else {
      pid = try await withRemoteInstrumentsClient { client in
        try await bridgeFBFuture(client.launchApplication(configuration))
      }
    }
    return FBDeviceLaunchedApplication(
      processIdentifier: pid.int32Value,
      configuration: configuration,
      commands: self,
      queue: device.workQueue
    )
  }

  // MARK: Private

  fileprivate func killApplication(withProcessIdentifier processIdentifier: pid_t) async throws {
    try await withRemoteInstrumentsClient { client in
      try await bridgeFBFutureVoid(client.killProcess(processIdentifier))
    }
  }

  private func installedApplicationsData(_ returnAttributes: [String]) async throws -> [String: [String: Any]] {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    return try await device.withConnectedDevice(purpose: "installed_apps") { connectedDevice in
      let options: [String: Any] = [
        "ReturnAttributes": returnAttributes
      ]
      var applications = Unmanaged<CFDictionary>.passUnretained(NSDictionary() as CFDictionary)
      let status =
        connectedDevice.calls.LookupApplications?(
          connectedDevice.amDeviceRef,
          options as CFDictionary,
          &applications
        ) ?? -1
      if status != 0 {
        let errorMessage = connectedDevice.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
        throw FBDeviceApplicationError.applicationLookupFailed(status: status, message: errorMessage)
      }
      guard let result = applications.takeRetainedValue() as? [String: [String: Any]] else {
        throw FBDeviceApplicationError.applicationLookupMalformed
      }
      return result
    }
  }

  private func withRemoteInstrumentsClient<R>(_ body: (FBInstrumentsClient) async throws -> R) async throws -> R {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let usesSecureConnection = device.osVersion.version.majorVersion >= 14
    _ = try await device.ensureDeveloperDiskImageIsMounted()
    let serviceName = usesSecureConnection ? "com.apple.instruments.remoteserver.DVTSecureSocketProxy" : "com.apple.instruments.remoteserver"
    return try await device.withServiceConnection(serviceName) { connection in
      let client = try await bridgeFBFuture(FBInstrumentsClient.instrumentsClient(with: connection, logger: device.logger))
      return try await body(client)
    }
  }

  private func pidToRunningProcessName() async throws -> [NSNumber: String] {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    return try await device.withServiceConnection("com.apple.os_trace_relay") { connection in
      do {
        try connection.sendMessage(["Request": "PidList"])
      } catch {
        throw FBDeviceApplicationError.pidListRequestFailed(underlying: error)
      }
      do {
        _ = try connection.receive(1)
      } catch {
        throw FBDeviceApplicationError.pidListAcknowledgementFailed(underlying: error)
      }
      let response: Any
      do {
        response = try connection.receiveMessage()
      } catch {
        throw FBDeviceApplicationError.pidListResponseFailed(underlying: error)
      }
      guard let responseDict = response as? [String: Any] else {
        throw FBDeviceApplicationError.pidListResponseNotADictionary(response: String(describing: response))
      }
      let status = responseDict["Status"] as? String
      if status != "RequestSuccessful" {
        throw FBDeviceApplicationError.pidListRequestUnsuccessful
      }
      let payload = responseDict["Payload"] as? [NSNumber: Any] ?? [:]
      var pidToRunningProcessName: [NSNumber: String] = [:]
      for (processIdentifier, value) in payload {
        guard let contents = value as? [String: Any],
          let processName = contents["ProcessName"] as? String
        else {
          continue
        }
        pidToRunningProcessName[processIdentifier] = processName
      }
      return pidToRunningProcessName
    }
  }

  private static func installedApplication(from app: [String: Any]) throws -> FBInstalledApplication {
    let bundleName = app[FBApplicationInstallInfoKey.bundleName.rawValue] as? String ?? ""
    let path = app[FBApplicationInstallInfoKey.path.rawValue] as? String ?? ""
    guard let bundleID = app[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] as? String else {
      throw FBDeviceApplicationError.missingBundleIdentifier(key: FBApplicationInstallInfoKey.bundleIdentifier.rawValue, application: String(describing: app))
    }

    let bundle = FBBundleDescriptor(name: bundleName, identifier: bundleID, path: path, binary: nil)

    return FBInstalledApplication.installedApplication(
      withBundle: bundle,
      installTypeString: app[FBApplicationInstallInfoKey.applicationType.rawValue] as? String ?? "",
      signerIdentity: app[FBApplicationInstallInfoKey.signerIdentity.rawValue] as? String ?? "",
      dataContainer: nil
    )
  }

  private static let installedApplicationLookupAttributes: [String] = [
    FBApplicationInstallInfoKey.applicationType.rawValue,
    FBApplicationInstallInfoKey.bundleIdentifier.rawValue,
    FBApplicationInstallInfoKey.bundleName.rawValue,
    FBApplicationInstallInfoKey.path.rawValue,
    FBApplicationInstallInfoKey.signerIdentity.rawValue,
  ]

  private static let namingLookupAttributes: [String] = [
    FBApplicationInstallInfoKey.bundleIdentifier.rawValue,
    FBApplicationInstallInfoKey.bundleName.rawValue,
  ]
}

// MARK: - FBDevice+ApplicationCommands

extension FBDevice: ApplicationCommands {

  public func installApplication(atPath path: String) async throws -> FBInstalledApplication {
    try await application.installApplication(withPath: path)
  }

  public func uninstallApplication(bundleID: String) async throws {
    try await application.uninstallApplication(withBundleID: bundleID)
  }

  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    try await application.launchApplication(configuration)
  }

  public func killApplication(bundleID: String) async throws {
    try await application.killApplication(withBundleID: bundleID)
  }

  public func installedApplications() async throws -> [FBInstalledApplication] {
    try await application.installedApplications()
  }

  public func installedApplication(bundleID: String) async throws -> FBInstalledApplication {
    try await application.installedApplication(withBundleID: bundleID)
  }

  public func runningApplications() async throws -> [String: pid_t] {
    let dict = try await application.runningApplications()
    return dict.mapValues { $0.int32Value }
  }

  public func processID(forBundleID bundleID: String) async throws -> pid_t {
    let pid = try await application.processID(withBundleID: bundleID)
    return pid.int32Value
  }
}
