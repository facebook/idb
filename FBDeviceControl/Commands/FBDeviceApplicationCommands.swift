/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

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

  // MARK: FBApplicationCommands Implementation

  @objc public func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication> {
    let bundle: FBBundleDescriptor
    do {
      bundle = try FBBundleDescriptor.bundle(fromPath: path)
    } catch {
      return FBFuture(error: error)
    }

    let appURL = URL(fileURLWithPath: path, isDirectory: true)
    let options: [String: Any] = [
      "CFBundleIdentifier": bundle.identifier,
      "CloseOnInvalidate": 1,
      "InvalidateOnDetach": 1,
      "IsUserInitiated": 1,
      "PackageType": "Developer",
      "ShadowParentKey": deltaUpdateDirectory,
    ]

    return device!.connectToDevice(withPurpose: "install").onQueue(
      device!.workQueue,
      pop: { (d: AnyObject) -> FBFuture<AnyObject> in
        let device = d as! any FBDeviceCommands
        self.device!.logger?.log("Installing Application \(appURL)")
        let statistics = FBDeviceWorkflowStatistics(workflowType: "Install", logger: device.logger)
        let context = Unmanaged.passUnretained(statistics).toOpaque()
        let status =
          device.calls.SecureInstallApplicationBundle?(
            device.amDeviceRef,
            appURL as CFURL,
            options as CFDictionary,
            workflowCallback,
            context
          ) ?? -1
        if status != 0 {
          let errorMessage = device.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
          return FBDeviceControlError.describe("Failed to install application \(appURL.lastPathComponent) 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(errorMessage)). \(statistics.summaryOfRecentEvents)").failFuture()
        }
        self.device!.logger?.log("Installed Application \(appURL)")
        return FBFuture<NSNull>.empty() as! FBFuture<AnyObject>
      }
    ).onQueue(
      device!.asyncQueue,
      fmap: { (_: AnyObject) -> FBFuture<AnyObject> in
        return self.installedApplication(withBundleID: bundle.identifier) as! FBFuture<AnyObject>
      }) as! FBFuture<FBInstalledApplication>
  }

  @objc public func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    return device!.connectToDevice(withPurpose: "uninstall_\(bundleID)").onQueue(
      device!.workQueue,
      pop: { (d: AnyObject) -> FBFuture<AnyObject> in
        let device = d as! any FBDeviceCommands
        let statistics = FBDeviceWorkflowStatistics(workflowType: "Uninstall", logger: device.logger)
        self.device!.logger?.log("Uninstalling Application \(bundleID)")
        let context = Unmanaged.passUnretained(statistics).toOpaque()
        let status =
          device.calls.SecureUninstallApplication?(
            nil,
            device.amDeviceRef,
            bundleID as CFString,
            0,
            workflowCallback,
            context
          ) ?? -1
        if status != 0 {
          let internalMessage = device.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
          return FBDeviceControlError.describe("Failed to uninstall application '\(bundleID)' with error 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(internalMessage)). \(statistics.summaryOfRecentEvents)").failFuture()
        }
        self.device!.logger?.log("Uninstalled Application \(bundleID)")
        return FBFuture<NSNull>.empty() as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
  }

  @objc public func installedApplications() -> FBFuture<NSArray> {
    return installedApplicationsData(Self.installedApplicationLookupAttributes).onQueue(
      device!.asyncQueue,
      map: { (data: AnyObject) -> AnyObject in
        let applicationData = data as! [String: [String: Any]]
        var installedApplications: [FBInstalledApplication] = []
        for app in applicationData.values {
          let application = FBDeviceApplicationCommands.installedApplication(from: app)
          installedApplications.append(application)
        }
        return installedApplications as NSArray as AnyObject
      }) as! FBFuture<NSArray>
  }

  @objc public func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication> {
    return installedApplicationsData(Self.installedApplicationLookupAttributes).onQueue(
      device!.asyncQueue,
      fmap: { (data: AnyObject) -> FBFuture<AnyObject> in
        let applicationData = data as! [String: [String: Any]]
        guard let app = applicationData[bundleID] else {
          return FBDeviceControlError.describe("Application with bundle ID: \(bundleID) is not installed. Installed apps \(FBCollectionInformation.oneLineDescription(from: Array(applicationData.keys) as [Any]))").failFuture()
        }
        let application = FBDeviceApplicationCommands.installedApplication(from: app)
        return FBFuture(result: application as AnyObject)
      }) as! FBFuture<FBInstalledApplication>
  }

  @objc public func runningApplications() -> FBFuture<NSDictionary> {
    return FBFuture<AnyObject>.combine([
      unsafeBitCast(pidToRunningProcessName(), to: FBFuture<AnyObject>.self),
      unsafeBitCast(installedApplicationsData(Self.namingLookupAttributes), to: FBFuture<AnyObject>.self),
    ])
    .onQueue(
      device!.asyncQueue,
      map: { results -> AnyObject in
        let tuple = results as [AnyObject]
        let pidToRunningProcessName = tuple[0] as! [NSNumber: String]
        let bundleIdentifierToAttributes = tuple[1] as! [String: [String: Any]]

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
        return bundleNameToPID as NSDictionary as AnyObject
      }) as! FBFuture<NSDictionary>
  }

  @objc public func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    return runningApplications().onQueue(
      device!.asyncQueue,
      fmap: { (result: AnyObject) -> FBFuture<AnyObject> in
        let running = result as! [String: NSNumber]
        guard let pid = running[bundleID] else {
          return FBDeviceControlError.describe("No pid for \(bundleID)").failFuture()
        }
        return FBFuture(result: pid as AnyObject)
      }) as! FBFuture<NSNumber>
  }

  @objc public func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    return processID(withBundleID: bundleID).onQueue(
      device!.workQueue,
      fmap: { (pid: AnyObject) -> FBFuture<AnyObject> in
        let processIdentifier = (pid as! NSNumber).int32Value
        return self.killApplication(withProcessIdentifier: processIdentifier) as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
  }

  @objc public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<any FBLaunchedApplication> {
    if device!.osVersion.version.majorVersion >= 17 {
      let devicectl = FBAppleDevicectlCommandExecutor(device: device!)
      return devicectl.launchApplication(configuration: configuration).onQueue(
        device!.asyncQueue,
        map: { (pid: AnyObject) -> AnyObject in
          let pidNumber = pid as! NSNumber
          return FBDeviceLaunchedApplication(
            processIdentifier: pidNumber.int32Value,
            configuration: configuration,
            commands: self,
            queue: self.device!.workQueue
          ) as AnyObject
        }) as! FBFuture<any FBLaunchedApplication>
    } else {
      return remoteInstrumentsClient().onQueue(
        device!.asyncQueue,
        pop: { (client: AnyObject) -> FBFuture<AnyObject> in
          let instrumentsClient = client as! FBInstrumentsClient
          return instrumentsClient.launchApplication(configuration) as! FBFuture<AnyObject>
        }
      ).onQueue(
        device!.asyncQueue,
        map: { (pid: AnyObject) -> AnyObject in
          let pidNumber = pid as! NSNumber
          return FBDeviceLaunchedApplication(
            processIdentifier: pidNumber.int32Value,
            configuration: configuration,
            commands: self,
            queue: self.device!.workQueue
          ) as AnyObject
        }) as! FBFuture<any FBLaunchedApplication>
    }
  }

  // MARK: Private

  fileprivate func killApplication(withProcessIdentifier processIdentifier: pid_t) -> FBFuture<NSNull> {
    return remoteInstrumentsClient().onQueue(
      device!.asyncQueue,
      pop: { (client: AnyObject) -> FBFuture<AnyObject> in
        let instrumentsClient = client as! FBInstrumentsClient
        return instrumentsClient.killProcess(processIdentifier) as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
  }

  private func installedApplicationsData(_ returnAttributes: [String]) -> FBFuture<NSDictionary> {
    return device!.connectToDevice(withPurpose: "installed_apps").onQueue(
      device!.workQueue,
      pop: { (d: AnyObject) -> FBFuture<AnyObject> in
        let device = d as! any FBDeviceCommands
        let options: [String: Any] = [
          "ReturnAttributes": returnAttributes
        ]
        var applications = Unmanaged<CFDictionary>.passUnretained(NSDictionary() as CFDictionary)
        let status =
          device.calls.LookupApplications?(
            device.amDeviceRef,
            options as CFDictionary,
            &applications
          ) ?? -1
        if status != 0 {
          let errorMessage = device.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
          return FBDeviceControlError.describe("Failed to get list of applications 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(errorMessage))").failFuture()
        }
        let result = applications.takeRetainedValue()
        return FBFuture(result: result as AnyObject)
      }) as! FBFuture<NSDictionary>
  }

  private func remoteInstrumentsClient() -> FBFutureContext<FBInstrumentsClient> {
    let usesSecureConnection = device!.osVersion.version.majorVersion >= 14
    return unsafeBitCast(
      device!.ensureDeveloperDiskImageIsMounted()
        .onQueue(
          device!.workQueue,
          pushTeardown: { (_: AnyObject) -> FBFutureContext<AnyObject> in
            let serviceName = usesSecureConnection ? "com.apple.instruments.remoteserver.DVTSecureSocketProxy" : "com.apple.instruments.remoteserver"
            return unsafeBitCast(self.device!.startService(serviceName), to: FBFutureContext<AnyObject>.self)
          }
        )
        .onQueue(
          device!.asyncQueue,
          pend: { (connection: AnyObject) -> FBFuture<AnyObject> in
            let conn = connection as! FBAMDServiceConnection
            return FBInstrumentsClient.instrumentsClient(with: conn, logger: self.device!.logger!) as! FBFuture<AnyObject>
          }),
      to: FBFutureContext<FBInstrumentsClient>.self
    )
  }

  private func pidToRunningProcessName() -> FBFuture<NSDictionary> {
    return device!.startService("com.apple.os_trace_relay").onQueue(
      device!.asyncQueue,
      pop: { (connection: AnyObject) -> FBFuture<AnyObject> in
        let conn = connection as! FBAMDServiceConnection
        do {
          try conn.sendMessage(["Request": "PidList"])
        } catch {
          return FBDeviceControlError.describe("Failed to request PidList \(error)").failFuture()
        }
        do {
          _ = try conn.receive(1)
        } catch {
          return FBDeviceControlError.describe("Failed to receive 1 byte after PidList \(error)").failFuture()
        }
        let response: Any
        do {
          response = try conn.receiveMessage()
        } catch {
          return FBDeviceControlError.describe("Failed to receive PidList response \(error)").failFuture()
        }
        let responseDict = response as! [String: Any]
        let status = responseDict["Status"] as? String
        if status != "RequestSuccessful" {
          return FBDeviceControlError.describe("Request to PidList is not RequestSuccessful").failFuture()
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
        return FBFuture(result: pidToRunningProcessName as NSDictionary as AnyObject)
      }) as! FBFuture<NSDictionary>
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
