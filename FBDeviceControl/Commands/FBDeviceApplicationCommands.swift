/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// swiftlint:disable force_cast force_unwrapping

// MARK: - FBDeviceWorkflowStatistics

private class FBDeviceWorkflowStatistics: NSObject {
  let workflowType: String
  let logger: any FBControlCoreLogger
  var lastEvent: [String: Any]?

  init(workflowType: String, logger: any FBControlCoreLogger) {
    self.workflowType = workflowType
    self.logger = logger
    super.init()
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

private class FBDeviceLaunchedApplication: NSObject, FBLaunchedApplication {
  let processIdentifier: pid_t
  private let _configuration: FBApplicationLaunchConfiguration
  private let commands: FBDeviceApplicationCommands
  private let queue: DispatchQueue

  init(processIdentifier: pid_t, configuration: FBApplicationLaunchConfiguration, commands: FBDeviceApplicationCommands, queue: DispatchQueue) {
    self.processIdentifier = processIdentifier
    self._configuration = configuration
    self.commands = commands
    self.queue = queue
    super.init()
  }

  var applicationTerminated: FBFuture<NSNull> {
    let commands = self.commands
    let processIdentifier = self.processIdentifier
    return unsafeBitCast(
      FBMutableFuture<NSNull>()
        .onQueue(
          queue,
          respondToCancellation: {
            return commands.killApplication(withProcessIdentifier: processIdentifier)
          }),
      to: FBFuture<NSNull>.self
    )
  }

  var bundleID: String {
    return _configuration.bundleID
  }
}

// MARK: - FBDeviceApplicationCommands

@objc(FBDeviceApplicationCommands)
public class FBDeviceApplicationCommands: NSObject, FBApplicationCommands {
  fileprivate weak var device: FBDevice?
  private let deltaUpdateDirectory: URL

  // MARK: Initializers

  @objc public class func commands(with target: any FBiOSTarget) -> Self {
    let device = target as! FBDevice
    let deltaUpdateDirectory = device.temporaryDirectory.temporaryDirectory()
    return unsafeDowncast(FBDeviceApplicationCommands(device: device, deltaUpdateDirectory: deltaUpdateDirectory), to: self)
  }

  init(device: FBDevice, deltaUpdateDirectory: URL) {
    self.device = device
    self.deltaUpdateDirectory = deltaUpdateDirectory
    super.init()
  }

  // MARK: FBApplicationCommands (legacy FBFuture entry points)

  @objc public func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication> {
    fbFutureFromAsync { [self] in
      try await installApplicationAsync(withPath: path)
    }
  }

  @objc public func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await uninstallApplicationAsync(withBundleID: bundleID)
      return NSNull()
    }
  }

  @objc public func installedApplications() -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await installedApplicationsAsync() as NSArray
    }
  }

  @objc public func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication> {
    fbFutureFromAsync { [self] in
      try await installedApplicationAsync(withBundleID: bundleID)
    }
  }

  @objc public func runningApplications() -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await runningApplicationsAsync() as NSDictionary
    }
  }

  @objc public func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    fbFutureFromAsync { [self] in
      try await processIDAsync(withBundleID: bundleID) as NSNumber
    }
  }

  @objc public func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await killApplicationAsync(withBundleID: bundleID)
      return NSNull()
    }
  }

  @objc public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<any FBLaunchedApplication> {
    fbFutureFromAsync { [self] in
      try await launchApplicationAsync(configuration)
    }
  }

  // MARK: - Async

  fileprivate func installApplicationAsync(withPath path: String) async throws -> FBInstalledApplication {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
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
    try await withFBFutureContext(device.connectToDevice(withPurpose: "install")) { connectedDevice in
      device.logger?.log("Installing Application \(appURL)")
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
        throw FBDeviceControlError.describe("Failed to install application \(appURL.lastPathComponent) 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(errorMessage)). \(statistics.summaryOfRecentEvents)").build()
      }
      device.logger?.log("Installed Application \(appURL)")
    }
    return try await installedApplicationAsync(withBundleID: bundle.identifier)
  }

  fileprivate func uninstallApplicationAsync(withBundleID bundleID: String) async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    try await withFBFutureContext(device.connectToDevice(withPurpose: "uninstall_\(bundleID)")) { connectedDevice in
      let statistics = FBDeviceWorkflowStatistics(workflowType: "Uninstall", logger: connectedDevice.logger)
      device.logger?.log("Uninstalling Application \(bundleID)")
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
        throw FBDeviceControlError.describe("Failed to uninstall application '\(bundleID)' with error 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(internalMessage)). \(statistics.summaryOfRecentEvents)").build()
      }
      device.logger?.log("Uninstalled Application \(bundleID)")
    }
  }

  fileprivate func installedApplicationsAsync() async throws -> [FBInstalledApplication] {
    let applicationData = try await installedApplicationsDataAsync(Self.installedApplicationLookupAttributes)
    var installedApplications: [FBInstalledApplication] = []
    for app in applicationData.values {
      let application = FBDeviceApplicationCommands.installedApplication(from: app)
      installedApplications.append(application)
    }
    return installedApplications
  }

  fileprivate func installedApplicationAsync(withBundleID bundleID: String) async throws -> FBInstalledApplication {
    let applicationData = try await installedApplicationsDataAsync(Self.installedApplicationLookupAttributes)
    guard let app = applicationData[bundleID] else {
      throw FBDeviceControlError.describe("Application with bundle ID: \(bundleID) is not installed. Installed apps \(FBCollectionInformation.oneLineDescription(from: Array(applicationData.keys) as [Any]))").build()
    }
    return FBDeviceApplicationCommands.installedApplication(from: app)
  }

  fileprivate func runningApplicationsAsync() async throws -> [String: NSNumber] {
    // Sequential rather than parallel: Swift 6 strict concurrency would
    // require Sendable captures of self/device for `async let` here.
    let pidToRunningProcessName = try await pidToRunningProcessNameAsync()
    let bundleIdentifierToAttributes = try await installedApplicationsDataAsync(Self.namingLookupAttributes)
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

  fileprivate func processIDAsync(withBundleID bundleID: String) async throws -> NSNumber {
    let running = try await runningApplicationsAsync()
    guard let pid = running[bundleID] else {
      throw FBDeviceControlError.describe("No pid for \(bundleID)").build()
    }
    return pid
  }

  fileprivate func killApplicationAsync(withBundleID bundleID: String) async throws {
    let pid = try await processIDAsync(withBundleID: bundleID)
    try await killApplicationAsync(withProcessIdentifier: pid.int32Value)
  }

  fileprivate func launchApplicationAsync(_ configuration: FBApplicationLaunchConfiguration) async throws -> any FBLaunchedApplication {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let pid: NSNumber
    if device.osVersion.version.majorVersion >= 17 {
      let devicectl = FBAppleDevicectlCommandExecutor(device: device)
      pid = try await devicectl.launchApplicationAsync(configuration: configuration)
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

  fileprivate func killApplication(withProcessIdentifier processIdentifier: pid_t) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await killApplicationAsync(withProcessIdentifier: processIdentifier)
      return NSNull()
    }
  }

  fileprivate func killApplicationAsync(withProcessIdentifier processIdentifier: pid_t) async throws {
    try await withRemoteInstrumentsClient { client in
      try await bridgeFBFutureVoid(client.killProcess(processIdentifier))
    }
  }

  private func installedApplicationsDataAsync(_ returnAttributes: [String]) async throws -> [String: [String: Any]] {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.connectToDevice(withPurpose: "installed_apps")) { connectedDevice in
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
        throw FBDeviceControlError.describe("Failed to get list of applications 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(errorMessage))").build()
      }
      let result = applications.takeRetainedValue() as NSDictionary
      return result as! [String: [String: Any]]
    }
  }

  private func withRemoteInstrumentsClient<R>(_ body: (FBInstrumentsClient) async throws -> R) async throws -> R {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let usesSecureConnection = device.osVersion.version.majorVersion >= 14
    _ = try await bridgeFBFuture(device.ensureDeveloperDiskImageIsMounted())
    let serviceName = usesSecureConnection ? "com.apple.instruments.remoteserver.DVTSecureSocketProxy" : "com.apple.instruments.remoteserver"
    return try await withFBFutureContext(device.startService(serviceName)) { connection in
      let client = try await bridgeFBFuture(FBInstrumentsClient.instrumentsClient(with: connection, logger: device.logger!))
      return try await body(client)
    }
  }

  private func pidToRunningProcessNameAsync() async throws -> [NSNumber: String] {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.startService("com.apple.os_trace_relay")) { connection in
      do {
        try connection.sendMessage(["Request": "PidList"])
      } catch {
        throw FBDeviceControlError.describe("Failed to request PidList \(error)").build()
      }
      do {
        _ = try connection.receive(1)
      } catch {
        throw FBDeviceControlError.describe("Failed to receive 1 byte after PidList \(error)").build()
      }
      let response: Any
      do {
        response = try connection.receiveMessage()
      } catch {
        throw FBDeviceControlError.describe("Failed to receive PidList response \(error)").build()
      }
      let responseDict = response as! [String: Any]
      let status = responseDict["Status"] as? String
      if status != "RequestSuccessful" {
        throw FBDeviceControlError.describe("Request to PidList is not RequestSuccessful").build()
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

  private static func installedApplication(from app: [String: Any]) -> FBInstalledApplication {
    let bundleName = app[FBApplicationInstallInfoKey.bundleName.rawValue] as? String ?? ""
    let path = app[FBApplicationInstallInfoKey.path.rawValue] as? String ?? ""
    let bundleID = app[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] as! String

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
