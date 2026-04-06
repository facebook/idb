/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// Helper to call [FBFuture futureWithFutures:] which is NS_SWIFT_UNAVAILABLE.
private func combineFutures(_ futures: [FBFuture<AnyObject>]) -> FBFuture<AnyObject> {
  let sel = NSSelectorFromString("futureWithFutures:")
  let method = FBFuture<AnyObject>.method(for: sel)
  typealias Signature = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
  let impl = unsafeBitCast(method, to: Signature.self)
  return impl(FBFuture<AnyObject>.self, sel, futures as NSArray)
}

@objc(FBSimulatorApplicationCommands)
public final class FBSimulatorApplicationCommands: NSObject, FBApplicationCommands, FBSimulatorApplicationCommandsProtocol, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorApplicationCommands {
    return FBSimulatorApplicationCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBApplicationCommands

  @objc
  public func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication> {
    return
      (unsafeBitCast(confirmCompatibilityOfApplication(atPath: path), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator!.workQueue,
        fmap: { [weak self] (appBundleObj: Any) -> FBFuture<AnyObject> in
          guard let self = self, let simulator = self.simulator else {
            return FBSimulatorError.describe("Simulator deallocated").failFuture()
          }
          let appBundle = appBundleObj as! FBBundleDescriptor
          let options: [String: Any] = ["CFBundleIdentifier": appBundle.identifier]
          let appURL = URL(fileURLWithPath: appBundle.path)
          var installError: AnyObject?
          if simulator.device.installApplication(appURL, withOptions: options as [AnyHashable: Any], error: &installError) {
            let f: FBFuture<FBInstalledApplication> = self.installedApplication(withBundleID: appBundle.identifier)
            return unsafeBitCast(f, to: FBFuture<AnyObject>.self)
          }

          // Retry install if the first attempt failed with 'Failed to load Info.plist...'.
          if let err = installError as? NSError, err.description.contains("Failed to load Info.plist from bundle at path") {
            simulator.logger?.log("Retrying install due to reinstall bug")
            var retryError: AnyObject?
            if simulator.device.installApplication(appURL, withOptions: options as [AnyHashable: Any], error: &retryError) {
              let f: FBFuture<FBInstalledApplication> = self.installedApplication(withBundleID: appBundle.identifier)
              return unsafeBitCast(f, to: FBFuture<AnyObject>.self)
            }
          }

          return FBSimulatorError.describe("Failed to install Application \(appBundle) with options \(options)")
            .failFuture()
        })) as! FBFuture<FBInstalledApplication>
  }

  @objc
  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<FBLaunchedApplication> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<FBLaunchedApplication>
    }
    let io = configuration.io
    let futures: [FBFuture<AnyObject>] = [
      unsafeBitCast(ensureApplicationIsInstalled(configuration.bundleID), to: FBFuture<AnyObject>.self),
      unsafeBitCast(confirmApplicationLaunchState(configuration.bundleID, launchMode: configuration.launchMode, waitForDebugger: configuration.waitForDebugger), to: FBFuture<AnyObject>.self),
    ]
    return
      (combineFutures(futures)
      .onQueue(
        simulator.workQueue,
        fmap: { (_: Any) -> FBFuture<AnyObject> in
          return unsafeBitCast(io.attachViaFile(), to: FBFuture<AnyObject>.self)
        }
      )
      .onQueue(
        simulator.workQueue,
        fmap: { [weak self] (attachmentObj: Any) -> FBFuture<AnyObject> in
          guard let self = self else {
            return FBSimulatorError.describe("Simulator deallocated").failFuture()
          }
          let attachment = attachmentObj as! FBProcessFileAttachment
          let launch = self.launchApplication(configuration, stdOut: attachment.stdOut!, stdErr: attachment.stdErr!)
          return unsafeBitCast(
            FBSimulatorLaunchedApplication.application(withSimulator: simulator, configuration: configuration, attachment: attachment, launchFuture: launch),
            to: FBFuture<AnyObject>.self)
        })) as! FBFuture<FBLaunchedApplication>
  }

  @objc
  public func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    let simDevice = simulator.device
    return FBFuture.onQueue(
      simulator.workQueue,
      resolveValue: { (error: NSErrorPointer) -> NSNull? in
        do {
          try simDevice.terminateApplication(withID: bundleID)
          return NSNull()
        } catch let e as NSError {
          error?.pointee = e
          return nil
        }
      })
  }

  @objc
  public func installedApplications() -> FBFuture<NSArray> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSArray>
    }
    return
      ((FBFuture.onQueue(
        simulator.workQueue,
        resolveValue: { (error: NSErrorPointer) -> NSDictionary? in
          do {
            return try FBSimDeviceWrapper.installedApps(onDevice: simulator.device) as NSDictionary
          } catch let e as NSError {
            error?.pointee = e
            return nil
          }
        }) as FBFuture)
      .onQueue(
        simulator.asyncQueue,
        map: { (installedAppsObj: Any) -> NSArray in
          let installedApps = installedAppsObj as! [String: Any]
          var applications: [FBInstalledApplication] = []
          for appInfo in installedApps.values {
            guard let dict = appInfo as? [String: Any],
              let application = FBSimulatorApplicationCommands.installedApplication(fromInfo: dict, error: nil)
            else {
              continue
            }
            applications.append(application)
          }
          return applications as NSArray
        })) as! FBFuture<NSArray>
  }

  @objc
  public func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    let instFuture: FBFuture<FBInstalledApplication> = simulator.installedApplication(withBundleID: bundleID)
    return
      (unsafeBitCast(instFuture, to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.asyncQueue,
        fmap: { (installedAppObj: Any) -> FBFuture<AnyObject> in
          let installedApplication = installedAppObj as! FBInstalledApplication
          if installedApplication.installType == .system {
            return FBSimulatorError.describe("Can't uninstall '\(installedApplication)' as it is a system Application")
              .failFuture()
          }
          return FBFuture(result: installedApplication)
        }
      )
      .onQueue(
        simulator.workQueue,
        fmap: { (_: Any) -> FBFuture<AnyObject> in
          return unsafeBitCast(
            (simulator.killApplication(withBundleID: bundleID) as FBFuture).fallback(NSNull()),
            to: FBFuture<AnyObject>.self)
        }
      )
      .onQueue(
        simulator.workQueue,
        fmap: { (_: Any) -> FBFuture<AnyObject> in
          var uninstallError: AnyObject?
          if !simulator.device.uninstallApplication(bundleID, withOptions: nil, error: &uninstallError) {
            return FBSimulatorError.describe("Failed to uninstall '\(bundleID)'")
              .failFuture()
          }
          return FBFuture(result: NSNull())
        })) as! FBFuture<NSNull>
  }

  @objc
  public func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<FBInstalledApplication>
    }
    return FBFuture.onQueue(
      simulator.workQueue,
      resolveValue: { [weak self] (error: NSErrorPointer) -> FBInstalledApplication? in
        return self?.fetchInstalledApplication(bundleID: bundleID, error: error)
      })
  }

  @objc
  public func runningApplications() -> FBFuture<NSDictionary> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSDictionary>
    }
    return
      (unsafeBitCast(simulator.serviceNamesAndProcessIdentifiers(matching: FBSimulatorApplicationCommands.uiKitApplicationRegex), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.asyncQueue,
        map: { (serviceNameToProcessIdentifier: Any) -> NSDictionary in
          let dict = serviceNameToProcessIdentifier as! [String: NSNumber]
          var mapping: [String: NSNumber] = [:]
          for serviceName in dict.keys {
            if let bundleName = FBSimulatorLaunchCtlCommands.extractApplicationBundleIdentifier(fromServiceName: serviceName) {
              mapping[bundleName] = dict[serviceName]
            }
          }
          return mapping as NSDictionary
        })) as! FBFuture<NSDictionary>
  }

  @objc
  public func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNumber>
    }
    let pattern = "UIKitApplication:\(NSRegularExpression.escapedPattern(for: bundleID))(\\[|$)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return FBSimulatorError.describe("Couldn't build search pattern for '\(bundleID)'")
        .failFuture() as! FBFuture<NSNumber>
    }
    return
      (unsafeBitCast(simulator.firstServiceNameAndProcessIdentifier(matching: regex), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        map: { (result: Any) -> NSNumber in
          let arr = result as! [Any]
          return arr[1] as! NSNumber
        })) as! FBFuture<NSNumber>
  }

  // MARK: - FBSimulatorApplicationCommandsProtocol

  @objc
  public func installedApplication(withBundleID bundleID: String) throws -> FBInstalledApplication {
    var error: NSError?
    guard let result = fetchInstalledApplication(bundleID: bundleID, error: &error) else {
      throw error ?? FBSimulatorError.describe("Failed to get installed application '\(bundleID)'").build()
    }
    return result
  }

  // MARK: - Private

  private func fetchInstalledApplication(bundleID: String, error: NSErrorPointer) -> FBInstalledApplication? {
    guard let simulator = self.simulator else {
      FBSimulatorError.describe("Simulator deallocated").fail(error)
      return nil
    }
    let device = simulator.device
    var applicationType: NSString?
    do {
      try device.applicationIsInstalled(bundleID, type: &applicationType)
    } catch let appErr as NSError {
      error?.pointee = appErr
      return nil
    }
    let appInfo: [String: Any]
    do {
      appInfo = try device.properties(ofApplication: bundleID)
    } catch let e as NSError {
      error?.pointee = e
      return nil
    }
    guard let application = FBSimulatorApplicationCommands.installedApplication(fromInfo: appInfo, error: error) else {
      return nil
    }
    return application
  }

  private static let uiKitApplicationRegex: NSRegularExpression = {
    return try! NSRegularExpression(pattern: "UIKitApplication:", options: [])
  }()

  private func ensureApplicationIsInstalled(_ bundleID: String) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    let instFuture: FBFuture<FBInstalledApplication> = simulator.installedApplication(withBundleID: bundleID)
    return
      ((instFuture as FBFuture)
      .mapReplace(NSNull()) as FBFuture)
      .onQueue(
        simulator.asyncQueue,
        handleError: { (error: Error) -> FBFuture<AnyObject> in
          return FBSimulatorError.describe("App \(bundleID) can't be launched as it isn't installed: \(error)")
            .failFuture()
        }) as! FBFuture<NSNull>
  }

  private func confirmApplicationLaunchState(_ bundleID: String, launchMode: FBApplicationLaunchMode, waitForDebugger: Bool) -> FBFuture<NSNull> {
    if waitForDebugger && launchMode == .foregroundIfRunning {
      return FBSimulatorError.describe("'Foreground if running' and 'wait for debugger cannot be applied simultaneously")
        .failFuture() as! FBFuture<NSNull>
    }

    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return
      (unsafeBitCast(simulator.processID(withBundleID: bundleID), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.asyncQueue,
        chain: { [weak self] (processFuture: FBFuture<AnyObject>) -> FBFuture<AnyObject> in
          let processID = processFuture.result
          if processID == nil {
            return FBFuture(result: NSNull())
          }
          if launchMode == .failIfRunning {
            return FBSimulatorError.describe("App '\(bundleID)' can't be launched as it is already running (PID=\(processID!))")
              .failFuture()
          } else if launchMode == .relaunchIfRunning {
            guard let self = self else {
              return FBSimulatorError.describe("Simulator deallocated").failFuture()
            }
            return unsafeBitCast(self.killApplication(withBundleID: bundleID), to: FBFuture<AnyObject>.self)
          }
          return FBFuture(result: NSNull())
        })) as! FBFuture<NSNull>
  }

  private func launchApplication(_ configuration: FBApplicationLaunchConfiguration, stdOut: any FBProcessFileOutput, stdErr: any FBProcessFileOutput) -> FBFuture<NSNumber> {
    let readingFutures: [FBFuture<AnyObject>] = [
      unsafeBitCast(stdOut.startReading(), to: FBFuture<AnyObject>.self),
      unsafeBitCast(stdErr.startReading(), to: FBFuture<AnyObject>.self),
    ]
    let readingFuture = combineFutures(readingFutures)

    return
      (unsafeBitCast(
        launchApplication(configuration, stdOutPath: stdOut.filePath, stdErrPath: stdErr.filePath),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        simulator!.workQueue,
        fmap: { (result: Any) -> FBFuture<AnyObject> in
          return readingFuture.mapReplace(result as AnyObject)
        })) as! FBFuture<NSNumber>
  }

  @objc
  public func isApplicationRunning(_ bundleID: String) -> FBFuture<NSNumber> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNumber>
    }
    return
      (unsafeBitCast(simulator.processID(withBundleID: bundleID), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        chain: { (future: FBFuture<AnyObject>) -> FBFuture<AnyObject> in
          let processIdentifier = future.result
          return processIdentifier != nil ? FBFuture(result: NSNumber(value: true)) : FBFuture(result: NSNumber(value: false))
        })) as! FBFuture<NSNumber>
  }

  private func launchApplication(_ configuration: FBApplicationLaunchConfiguration, stdOutPath: String?, stdErrPath: String?) -> FBFuture<NSNumber> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNumber>
    }
    let options = FBSimulatorApplicationCommands.simDeviceLaunchOptions(
      for: configuration,
      stdOutPath: translateAbsolutePath(stdOutPath, toPathRelativeTo: simulator.dataDirectory!),
      stdErrPath: translateAbsolutePath(stdErrPath, toPathRelativeTo: simulator.dataDirectory!))

    let future = FBMutableFuture<NSNumber>()
    let logger = simulator.logger

    logger?.log("Launching Application \(configuration.bundleID) with \(FBCollectionInformation.oneLineDescription(from: configuration.arguments)) \(FBCollectionInformation.oneLineDescription(from: configuration.environment))")
    simulator.device.launchApplicationAsync(withID: configuration.bundleID, options: options, completionQueue: simulator.workQueue) { error, pid in
      if let error = error {
        logger?.log("Failed to launch Application \(configuration.bundleID) \(error)")
        future.resolveWithError(error)
      } else {
        logger?.log("Launched Application \(configuration.bundleID) with pid \(pid)")
        future.resolve(withResult: NSNumber(value: pid))
      }
    }
    return unsafeBitCast(future, to: FBFuture<NSNumber>.self)
  }

  private func translateAbsolutePath(_ absolutePath: String?, toPathRelativeTo referencePath: String) -> String? {
    guard let absolutePath = absolutePath else { return nil }
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
    if let stdOutPath = stdOutPath {
      options["stdout"] = stdOutPath
    }
    if let stdErrPath = stdErrPath {
      options["stderr"] = stdErrPath
    }
    return options
  }

  private static let keyDataContainer = "DataContainer"

  private class func installedApplication(fromInfo appInfo: [String: Any], error: NSErrorPointer) -> FBInstalledApplication? {
    guard let appName = appInfo[FBApplicationInstallInfoKey.bundleName.rawValue] as? String else {
      FBControlCoreError.describe("Bundle Name \(appInfo[FBApplicationInstallInfoKey.bundleName.rawValue] ?? "nil") is not a String for \(FBApplicationInstallInfoKey.bundleName.rawValue) in \(appInfo)").fail(error)
      return nil
    }
    guard let _ = appInfo[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] as? String else {
      FBControlCoreError.describe("Bundle Identifier \(appInfo[FBApplicationInstallInfoKey.bundleIdentifier.rawValue] ?? "nil") is not a String for \(FBApplicationInstallInfoKey.bundleIdentifier.rawValue) in \(appInfo)").fail(error)
      return nil
    }
    guard let appPath = appInfo[FBApplicationInstallInfoKey.path.rawValue] as? String else {
      FBControlCoreError.describe("App Path \(appInfo[FBApplicationInstallInfoKey.path.rawValue] ?? "nil") is not a String for \(FBApplicationInstallInfoKey.path.rawValue) in \(appInfo)").fail(error)
      return nil
    }
    guard let typeString = appInfo[FBApplicationInstallInfoKey.applicationType.rawValue] as? String else {
      FBControlCoreError.describe("Install Type \(appInfo[FBApplicationInstallInfoKey.applicationType.rawValue] ?? "nil") is not a String for \(FBApplicationInstallInfoKey.applicationType.rawValue) in \(appInfo)").fail(error)
      return nil
    }
    let dataContainer = appInfo[keyDataContainer]
    if let dataContainer = dataContainer, !(dataContainer is URL) {
      FBControlCoreError.describe("Data Container \(dataContainer) is not a NSURL for \(keyDataContainer) in \(appInfo)").fail(error)
      return nil
    }

    guard let bundle = try? FBBundleDescriptor.bundle(fromPath: appPath) else {
      return nil
    }

    let _ = appName // used for validation only
    return FBInstalledApplication.installedApplication(
      withBundle: bundle,
      installTypeString: typeString,
      signerIdentity: nil,
      dataContainer: (dataContainer as? URL)?.path)
  }

  private func confirmCompatibilityOfApplication(atPath path: String) -> FBFuture<FBBundleDescriptor> {
    guard let application = try? FBBundleDescriptor.bundle(fromPath: path) else {
      return FBSimulatorError.describe("Could not determine Application information for path \(path)")
        .failFuture() as! FBFuture<FBBundleDescriptor>
    }

    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<FBBundleDescriptor>
    }
    let installedFuture: FBFuture<FBInstalledApplication> = simulator.installedApplication(withBundleID: application.identifier)
    return
      (unsafeBitCast(installedFuture, to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        chain: { (future: FBFuture<AnyObject>) -> FBFuture<AnyObject> in
          let installed = future.result as? FBInstalledApplication
          if let installed = installed, installed.installType == .system {
            return FBSimulatorError.describe("Cannot install app as it is a system app \(installed)")
              .failFuture()
          }
          let binaryArchRawValues = Set(application.binary!.architectures.map { $0.rawValue })
          let supportedArchitectures = FBiOSTargetConfiguration.baseArchsToCompatibleArch(simulator.architectures)
          let supportedArchRawValues = Set(supportedArchitectures.map { $0.rawValue })
          if binaryArchRawValues.isDisjoint(with: supportedArchRawValues) {
            return FBSimulatorError.describe(
              "Simulator does not support any of the architectures (\(FBCollectionInformation.oneLineDescription(from: Array(binaryArchRawValues)))) of the executable at \(application.binary!.path). Simulator Archs (\(FBCollectionInformation.oneLineDescription(from: Array(supportedArchRawValues))))"
            )
            .failFuture()
          }
          return FBFuture(result: application)
        })) as! FBFuture<FBBundleDescriptor>
  }
}
