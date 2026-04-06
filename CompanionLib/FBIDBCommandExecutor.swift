// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
@_implementationOnly import FBDeviceControl
@_implementationOnly import FBSimulatorControl
import Foundation
import XCTestBootstrap

@objc public final class FBIDBCommandExecutor: NSObject {

  private let target: FBiOSTarget
  private let logger: FBIDBLogger
  private let debugserverPort: in_port_t

  @objc public let storageManager: FBIDBStorageManager
  @objc public var debugServer: FBDebugServer?
  @objc public let temporaryDirectory: FBTemporaryDirectory

  // MARK: - Initializers

  @objc public static func commandExecutor(forTarget target: FBiOSTarget, storageManager: FBIDBStorageManager, temporaryDirectory: FBTemporaryDirectory, debugserverPort: in_port_t, logger: FBIDBLogger) -> FBIDBCommandExecutor {
    return FBIDBCommandExecutor(target: target, storageManager: storageManager, temporaryDirectory: temporaryDirectory, debugserverPort: debugserverPort, logger: logger.withName("grpc_handler") as! FBIDBLogger)
  }

  private init(target: FBiOSTarget, storageManager: FBIDBStorageManager, temporaryDirectory: FBTemporaryDirectory, debugserverPort: in_port_t, logger: FBIDBLogger) {
    self.target = target
    self.storageManager = storageManager
    self.temporaryDirectory = temporaryDirectory
    self.debugserverPort = debugserverPort
    self.logger = logger
    super.init()
  }

  // MARK: - Installation

  @objc public func list_apps(_ fetchProcessState: Bool) -> FBFuture<NSDictionary> {
    let installedFuture: FBFuture<AnyObject> = target.installedApplications() as! FBFuture<AnyObject>
    let runningFuture: FBFuture<AnyObject> = fetchProcessState ? target.runningApplications() as! FBFuture<AnyObject> : FBFuture(result: NSDictionary())
    return
      installedFuture
      .onQueue(
        target.workQueue,
        fmap: { installed in
          runningFuture.onQueue(
            self.target.workQueue,
            map: { running -> AnyObject in
              let installedApps = installed as! [FBInstalledApplication]
              let runningApps = running as! [String: NSNumber]
              let listing = NSMutableDictionary()
              for application in installedApps {
                listing[application] = runningApps[application.bundle.identifier] ?? NSNull()
              }
              return listing
            })
        }) as! FBFuture<NSDictionary>
  }

  @objc public func install_app_file_path(_ filePath: String, make_debuggable makeDebuggable: Bool, override_modification_time overrideModificationTime: Bool) -> FBFuture<FBInstalledArtifact> {
    if FBBundleDescriptor.isApplication(atPath: filePath) {
      guard let bundleDescriptor = try? FBBundleDescriptor.bundle(fromPath: filePath) else {
        return FBFuture(error: FBControlCoreError.describe("Failed to read bundle at \(filePath)").build() as NSError)
      }
      return installAppBundle(FBFutureContext(result: bundleDescriptor as AnyObject), makeDebuggable: makeDebuggable)
    } else {
      return installExtractedApp(temporaryDirectory.withArchiveExtracted(fromFile: filePath, overrideModificationTime: overrideModificationTime) as! FBFutureContext<AnyObject>, makeDebuggable: makeDebuggable)
    }
  }

  @objc public func install_app_stream(_ input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, make_debuggable makeDebuggable: Bool, override_modification_time overrideModificationTime: Bool) -> FBFuture<FBInstalledArtifact> {
    return installExtractedApp(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: compression, overrideModificationTime: overrideModificationTime) as! FBFutureContext<AnyObject>, makeDebuggable: makeDebuggable)
  }

  @objc public func install_xctest_app_file_path(_ filePath: String, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    return installXctestFilePath(FBFutureContext(future: FBFuture(result: URL(fileURLWithPath: filePath) as AnyObject)), skipSigningBundles: skipSigningBundles)
  }

  @objc public func install_xctest_app_stream(_ stream: FBProcessInput<AnyObject>, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    return installXctest(temporaryDirectory.withArchiveExtracted(fromStream: stream, compression: .GZIP) as! FBFutureContext<AnyObject>, skipSigningBundles: skipSigningBundles)
  }

  @objc public func install_dylib_file_path(_ filePath: String) -> FBFuture<FBInstalledArtifact> {
    return installFile(FBFutureContext(future: FBFuture(result: URL(fileURLWithPath: filePath) as AnyObject)), intoStorage: storageManager.dylib)
  }

  @objc public func install_dylib_stream(_ input: FBProcessInput<AnyObject>, name: String) -> FBFuture<FBInstalledArtifact> {
    return installFile(temporaryDirectory.withGzipExtracted(fromStream: input, name: name) as! FBFutureContext<AnyObject>, intoStorage: storageManager.dylib)
  }

  @objc public func install_framework_file_path(_ filePath: String) -> FBFuture<FBInstalledArtifact> {
    return installBundle(FBFutureContext(future: FBFuture(result: URL(fileURLWithPath: filePath) as AnyObject)), intoStorage: storageManager.framework)
  }

  @objc public func install_framework_stream(_ input: FBProcessInput<AnyObject>) -> FBFuture<FBInstalledArtifact> {
    return installBundle(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: .GZIP) as! FBFutureContext<AnyObject>, intoStorage: storageManager.framework)
  }

  @objc public func install_dsym_file_path(_ filePath: String, linkTo: FBDsymInstallLinkToBundle?) -> FBFuture<FBInstalledArtifact> {
    return installAndLinkDsym(FBFutureContext(future: FBFuture(result: URL(fileURLWithPath: filePath) as AnyObject)), intoStorage: storageManager.dsym, linkTo: linkTo)
  }

  @objc public func install_dsym_stream(_ input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, linkTo: FBDsymInstallLinkToBundle?) -> FBFuture<FBInstalledArtifact> {
    return installAndLinkDsym(dsymDirnameFromUnzipDir(temporaryDirectory.withArchiveExtracted(fromStream: input, compression: compression) as! FBFutureContext<AnyObject>), intoStorage: storageManager.dsym, linkTo: linkTo)
  }

  // MARK: - Public Methods

  @objc public func take_screenshot(_ format: FBScreenshotFormat) -> FBFuture<NSData> {
    return screenshotCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBScreenshotCommands).takeScreenshot(format) as! FBFuture<AnyObject>
        }) as! FBFuture<NSData>
  }

  @objc public func accessibility_info_at_point(_ value: NSValue?, nestedFormat: Bool) -> FBFuture<FBAccessibilityElementsResponse> {
    return accessibilityCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          let cmds = commands as! FBAccessibilityCommands
          let options = FBAccessibilityRequestOptions.`default`()
          options.nestedFormat = nestedFormat
          options.enableLogging = true

          let elementFuture: FBFuture<AnyObject>
          if let value {
            elementFuture = cmds.accessibilityElement(at: value.pointValue) as! FBFuture<AnyObject>
          } else {
            elementFuture = cmds.accessibilityElementForFrontmostApplication() as! FBFuture<AnyObject>
          }
          return
            elementFuture
            .onQueue(
              self.target.workQueue,
              map: { element -> AnyObject in
                let elem = element as! FBAccessibilityElement
                let response = try? elem.serialize(with: options)
                elem.close()
                return response as AnyObject
              })
        }) as! FBFuture<FBAccessibilityElementsResponse>
  }

  @objc public func add_media(_ filePaths: [URL]) -> FBFuture<NSNull> {
    return mediaCommands()
      .onQueue(
        target.asyncQueue,
        fmap: { commands in
          (commands as! FBSimulatorMediaCommands).addMedia(filePaths) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func set_location(_ latitude: Double, longitude: Double) -> FBFuture<NSNull> {
    guard let commands = target as? FBLocationCommands else {
      return FBIDBError.describe("\(target) does not conform to FBLocationCommands").failFuture() as! FBFuture<NSNull>
    }
    return commands.overrideLocation(withLongitude: longitude, latitude: latitude)
  }

  @objc public func clear_keychain() -> FBFuture<NSNull> {
    return keychainCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorKeychainCommandsProtocol).clearKeychain() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func approve(_ services: Set<FBTargetSettingsService>, for_application bundleID: String) -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).grantAccess(Set([bundleID]), toServices: services) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func revoke(_ services: Set<FBTargetSettingsService>, for_application bundleID: String) -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).revokeAccess(Set([bundleID]), toServices: services) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func approve_deeplink(_ scheme: String, for_application bundleID: String) -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).grantAccess(Set([bundleID]), toDeeplink: scheme) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func revoke_deeplink(_ scheme: String, for_application bundleID: String) -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).revokeAccess(Set([bundleID]), toDeeplink: scheme) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func open_url(_ url: String) -> FBFuture<NSNull> {
    return lifecycleCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorLifecycleCommandsProtocol).open(URL(string: url)!) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func focus() -> FBFuture<NSNull> {
    return lifecycleCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorLifecycleCommandsProtocol).focus() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func update_contacts(_ dbTarData: Data) -> FBFuture<NSNull> {
    return (temporaryDirectory.withArchiveExtracted(dbTarData) as! FBFutureContext<AnyObject>)
      .onQueue(
        target.workQueue,
        pop: { tempDirectory in
          let tempDir = tempDirectory as! URL
          return self.settingsCommands()
            .onQueue(
              self.target.workQueue,
              fmap: { commands in
                (commands as! FBSimulatorSettingsCommands).updateContacts(tempDir.path) as! FBFuture<AnyObject>
              })
        }) as! FBFuture<NSNull>
  }

  @objc public func clear_contacts() -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).clearContacts() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func clear_photos() -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).clearPhotos() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func list_test_bundles() -> FBFuture<NSArray> {
    return FBFuture.onQueue(
      target.workQueue,
      resolve: {
        do {
          let testDescriptors = try self.storageManager.xctest.listTestDescriptors()
          return FBFuture(result: testDescriptors as NSArray)
        } catch {
          return FBFuture(error: error as NSError)
        }
      }) as! FBFuture<NSArray>
  }

  private static let ListTestBundleTimeout: TimeInterval = 180.0

  @objc public func list_tests_in_bundle(_ bundleID: String, with_app appPath: String?) -> FBFuture<NSArray> {
    var resolvedAppPath = appPath
    if resolvedAppPath == "" {
      resolvedAppPath = nil
    }

    if let app = resolvedAppPath, storageManager.application.persistedBundleIDs.contains(app) {
      resolvedAppPath = storageManager.application.persistedBundles[app]?.path
    }

    let finalAppPath = resolvedAppPath

    return FBFuture.onQueue(
      target.workQueue,
      resolve: {
        do {
          let testDescriptor = try self.storageManager.xctest.testDescriptor(withID: bundleID)
          typealias ListTestsFn = @convention(c) (AnyObject, Selector, NSString, TimeInterval, NSString?) -> AnyObject
          let sel = NSSelectorFromString("listTestsForBundleAtPath:timeout:withAppAtPath:")
          let imp = unsafeBitCast((self.target as AnyObject).method(for: sel), to: ListTestsFn.self)
          return imp(self.target as AnyObject, sel, testDescriptor.url.path as NSString, FBIDBCommandExecutor.ListTestBundleTimeout, finalAppPath as NSString?) as! FBFuture<AnyObject>
        } catch {
          return FBFuture(error: error as NSError)
        }
      }) as! FBFuture<NSArray>
  }

  @objc public func uninstall_application(_ bundleID: String) -> FBFuture<NSNull> {
    return target.uninstallApplication(withBundleID: bundleID)
  }

  @objc public func kill_application(_ bundleID: String) -> FBFuture<NSNull> {
    return target.killApplication(withBundleID: bundleID).fallback(NSNull())
  }

  @objc public func launch_app(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<FBLaunchedApplication> {
    var replacements: [String: String] = [:]
    replacements.merge(storageManager.replacementMapping) { _, new in new }
    replacements.merge(target.replacementMapping()) { _, new in new }
    let environment = applyEnvironmentReplacements(configuration.environment, replacements: replacements)

    let derived = FBApplicationLaunchConfiguration(
      bundleID: configuration.bundleID,
      bundleName: configuration.bundleName,
      arguments: configuration.arguments,
      environment: environment,
      waitForDebugger: configuration.waitForDebugger,
      io: configuration.io,
      launchMode: configuration.launchMode
    )
    return target.launchApplication(derived)
  }

  @objc public func crash_list(_ predicate: NSPredicate) -> FBFuture<NSArray> {
    return target.crashes(predicate, useCache: false)
      .onQueue(
        target.asyncQueue,
        map: { crashes -> AnyObject in
          return crashes
        }) as! FBFuture<NSArray>
  }

  @objc public func crash_show(_ predicate: NSPredicate) -> FBFuture<FBCrashLog> {
    return target.crashes(predicate, useCache: true)
      .onQueue(
        target.asyncQueue,
        fmap: { crashes in
          let crashArray = crashes as! [FBCrashLogInfo]
          if crashArray.count > 1 {
            return FBIDBError.describe("More than one crash log matching \(predicate)").failFuture()
          }
          if crashArray.isEmpty {
            return FBIDBError.describe("No crashes matching \(predicate)").failFuture()
          }
          do {
            let log = try crashArray.first!.obtainCrashLog()
            return FBFuture(result: log) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<FBCrashLog>
  }

  @objc public func crash_delete(_ predicate: NSPredicate) -> FBFuture<NSArray> {
    return target.pruneCrashes(predicate)
      .onQueue(
        target.asyncQueue,
        map: { crashes -> AnyObject in
          return crashes
        }) as! FBFuture<NSArray>
  }

  @objc public func xctest_run(_ request: FBXCTestRunRequest, reporter: FBXCTestReporter, logger: FBControlCoreLogger) -> FBFuture<FBIDBTestOperation> {
    return request.start(withBundleStorageManager: storageManager.xctest, target: target, reporter: reporter, logger: logger, temporaryDirectory: temporaryDirectory)
  }

  @objc public func debugserver_start(_ bundleID: String) -> FBFuture<AnyObject> {
    guard let commands = target as? FBDebuggerCommands else {
      return FBControlCoreError.describe("Target doesn't conform to FBDebuggerCommands protocol \(target)").failFuture()
    }

    return debugserver_prepare(bundleID)
      .onQueue(
        target.workQueue,
        fmap: { application in
          let app = application as! FBBundleDescriptor
          return commands.launchDebugServer(forHostApplication: app, port: self.debugserverPort) as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        target.workQueue,
        doOnResolved: { debugServer in
          self.debugServer = debugServer as? FBDebugServer
        })
  }

  @objc public func debugserver_status() -> FBFuture<AnyObject> {
    return FBFuture.onQueue(
      target.workQueue,
      resolve: {
        guard let debugServer = self.debugServer else {
          return FBControlCoreError.describe("No debug server running").failFuture()
        }
        return FBFuture(result: debugServer as AnyObject)
      })
  }

  @objc public func debugserver_stop() -> FBFuture<AnyObject> {
    return debugserver_status()
      .onQueue(
        target.workQueue,
        fmap: { debugServer in
          self.debugServer!.completed.cancel().mapReplace(debugServer)
        }
      )
      .onQueue(
        target.workQueue,
        doOnResolved: { _ in
          self.debugServer = nil
        })
  }

  @objc public func tail_companion_logs(_ consumer: FBDataConsumer) -> FBFuture<FBLogOperation> {
    return unsafeBitCast(logger.tailToConsumer(consumer), to: FBFuture<FBLogOperation>.self)
  }

  @objc public func diagnostic_information() -> FBFuture<NSDictionary> {
    guard let commands = target as? FBDiagnosticInformationCommands else {
      return FBFuture(result: NSDictionary())
    }
    return commands.fetchDiagnosticInformation()
  }

  @objc public func hid(_ event: NSObject) -> FBFuture<NSNull> {
    return connectToHID()
      .onQueue(
        target.workQueue,
        fmap: { hid in
          let performSel = NSSelectorFromString("performOnHID:")
          return event.perform(performSel, with: hid)!.takeUnretainedValue() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func set_hardware_keyboard_enabled(_ enabled: Bool) -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).setHardwareKeyboardEnabled(enabled) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func set_preference(_ name: String, value: String, type: String?, domain: String?) -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).setPreference(name, value: value, type: type, domain: domain) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func get_preference(_ name: String, domain: String?) -> FBFuture<NSString> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).getCurrentPreference(name, domain: domain) as! FBFuture<AnyObject>
        }) as! FBFuture<NSString>
  }

  @objc public func set_locale_with_identifier(_ identifier: String) -> FBFuture<NSNull> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).setPreference("AppleLocale", value: identifier, type: nil, domain: nil) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func get_current_locale_identifier() -> FBFuture<NSString> {
    return settingsCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          (commands as! FBSimulatorSettingsCommands).getCurrentPreference("AppleLocale", domain: nil) as! FBFuture<AnyObject>
        }) as! FBFuture<NSString>
  }

  @objc public func list_locale_identifiers() -> [String] {
    return NSLocale.availableLocaleIdentifiers
  }

  // MARK: - File Commands

  @objc public func move_paths(_ originPaths: [String], to_path destinationPath: String, containerType: String?) -> FBFuture<NSNull> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          let futures = originPaths.map { originPath in
            containerObj.move(from: originPath, to: destinationPath) as! FBFuture<AnyObject>
          }
          return Self.combineFutures(futures).mapReplace(NSNull())
        }) as! FBFuture<NSNull>
  }

  @objc public func push_file_from_tar(_ tarData: Data, to_path destinationPath: String, containerType: String?) -> FBFuture<NSNull> {
    return (temporaryDirectory.withArchiveExtracted(tarData) as! FBFutureContext<AnyObject>)
      .onQueue(
        target.workQueue,
        pop: { extractionDirectory in
          do {
            let extractDir = extractionDirectory as! URL
            let paths = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            return self.push_files(paths, to_path: destinationPath, containerType: containerType) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<NSNull>
  }

  @objc public func push_files(_ paths: [URL], to_path destinationPath: String, containerType: String?) -> FBFuture<NSNull> {
    return FBFuture.onQueue(
      target.asyncQueue,
      resolve: {
        return self.applicationDataContainerCommands(containerType)
          .onQueue(
            self.target.workQueue,
            pop: { container in
              let containerObj = container as! FBFileContainerProtocol
              let futures = paths.map { originPath in
                containerObj.copy(fromHost: originPath.path, toContainer: destinationPath) as! FBFuture<AnyObject>
              }
              return Self.combineFutures(futures).mapReplace(NSNull())
            })
      }) as! FBFuture<NSNull>
  }

  @objc public func pull_file_path(_ path: String, destination_path destinationPath: String?, containerType: String?) -> FBFuture<NSString> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          return containerObj.copy(fromContainer: path, toHost: destinationPath!) as! FBFuture<AnyObject>
        }) as! FBFuture<NSString>
  }

  @objc public func pull_file(_ path: String, containerType: String?) -> FBFuture<NSData> {
    var tempPath: String = ""

    return (temporaryDirectory.withTemporaryDirectory() as! FBFutureContext<AnyObject>)
      .onQueue(
        target.workQueue,
        pend: { url in
          let urlObj = url as! URL
          tempPath = (urlObj.path as NSString).appendingPathComponent((path as NSString).lastPathComponent)
          return self.applicationDataContainerCommands(containerType)
            .onQueue(
              self.target.workQueue,
              pop: { container in
                let containerObj = container as! FBFileContainerProtocol
                return containerObj.copy(fromContainer: path, toHost: tempPath) as! FBFuture<AnyObject>
              })
        }
      )
      .onQueue(
        target.workQueue,
        pop: { _ in
          return FBArchiveOperations.createGzippedTarData(forPath: tempPath, queue: self.target.workQueue, logger: self.target.logger!) as! FBFuture<AnyObject>
        }) as! FBFuture<NSData>
  }

  @objc public func tail(_ path: String, to_consumer consumer: FBDataConsumer, in_container containerType: String?) -> FBFuture<FBFuture<NSNull>> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          return containerObj.tail(path, to: consumer) as! FBFuture<AnyObject>
        }) as! FBFuture<FBFuture<NSNull>>
  }

  @objc public func create_directory(_ directoryPath: String, containerType: String) -> FBFuture<NSNull> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          return containerObj.createDirectory(directoryPath) as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func remove_paths(_ paths: [String], containerType: String?) -> FBFuture<NSNull> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          let futures = paths.map { path in
            containerObj.remove(path) as! FBFuture<AnyObject>
          }
          return Self.combineFutures(futures).mapReplace(NSNull())
        }) as! FBFuture<NSNull>
  }

  @objc public func list_path(_ path: String, containerType: String?) -> FBFuture<NSArray> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          return containerObj.contents(ofDirectory: path) as! FBFuture<AnyObject>
        }) as! FBFuture<NSArray>
  }

  @objc public func list_paths(_ paths: [String], containerType: String?) -> FBFuture<NSDictionary> {
    return applicationDataContainerCommands(containerType)
      .onQueue(
        target.workQueue,
        pop: { container in
          let containerObj = container as! FBFileContainerProtocol
          let futures = paths.map { path in
            containerObj.contents(ofDirectory: path) as! FBFuture<AnyObject>
          }
          return Self.combineFutures(futures)
        }
      )
      .onQueue(
        target.asyncQueue,
        map: { listings -> AnyObject in
          let listingsArray = listings as! [NSArray]
          return NSDictionary(objects: listingsArray, forKeys: paths as [NSString])
        }) as! FBFuture<NSDictionary>
  }

  @objc public func dapServer(withPath dapPath: String, stdIn: FBProcessInput<AnyObject>, stdOut: FBDataConsumer) -> FBFuture<AnyObject> {
    guard let commands = target as? FBDapServerCommand else {
      return FBControlCoreError.describe("Target doesn't conform to FBDapServerCommand protocol \(target)").failFuture()
    }
    return commands.launchDapServer(dapPath, stdIn: stdIn, stdOut: stdOut) as! FBFuture<AnyObject>
  }

  @objc public func clean() -> FBFuture<NSNull> {
    if target.state == .shutdown {
      return remove_all_storage_and_clear_keychain()
    }
    return uninstall_all_applications()
      .onQueue(
        target.workQueue,
        fmap: { _ in
          self.remove_all_storage_and_clear_keychain() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
  }

  @objc public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) -> FBFuture<NSNull> {
    guard let commands = target as? FBNotificationCommands else {
      return FBIDBError.describe("\(target) does not conform to FBNotificationCommands").failFuture() as! FBFuture<NSNull>
    }
    return commands.sendPushNotification(forBundleID: bundleID, jsonPayload: jsonPayload)
  }

  @objc public func simulateMemoryWarning() -> FBFuture<NSNull> {
    guard let commands = target as? FBMemoryCommands else {
      return FBIDBError.describe("\(target) does not conform to FBMemoryCommands").failFuture() as! FBFuture<NSNull>
    }
    return commands.simulateMemoryWarning()
  }

  // MARK: - Private Methods

  private static func combineFutures(_ futures: [FBFuture<AnyObject>]) -> FBFuture<AnyObject> {
    let cls = unsafeBitCast(NSClassFromString("FBFuture")!, to: NSObject.Type.self)
    let sel = NSSelectorFromString("futureWithFutures:")
    return cls.perform(sel, with: futures)!.takeUnretainedValue() as! FBFuture<AnyObject>
  }

  private func applyEnvironmentReplacements(_ environment: [String: String], replacements: [String: String]) -> [String: String] {
    logger.log("Original environment: \(environment)")
    logger.log("Existing replacement mapping: \(replacements)")
    var interpolatedEnvironment: [String: String] = [:]
    for (name, var value) in environment {
      for (interpolationName, interpolationValue) in replacements {
        value = value.replacingOccurrences(of: interpolationName, with: interpolationValue)
      }
      interpolatedEnvironment[name] = value
    }
    logger.log("Interpolated environment: \(interpolatedEnvironment)")
    return interpolatedEnvironment
  }

  private func remove_all_storage_and_clear_keychain() -> FBFuture<NSNull> {
    do {
      try storageManager.clean()
    } catch {
      return FBFuture(error: error as NSError)
    }
    return clear_keychain()
  }

  private func uninstall_all_applications() -> FBFuture<NSNull> {
    return list_apps(false)
      .onQueue(
        target.workQueue,
        fmap: { apps in
          let appsDict = apps as! [FBInstalledApplication: AnyObject]
          let uninstallFutures: [FBFuture<AnyObject>] = appsDict.keys.compactMap { app in
            guard app.installType == .user else { return nil }
            return self.kill_application(app.bundle.identifier)
              .onQueue(
                self.target.workQueue,
                fmap: { _ in
                  self.uninstall_application(app.bundle.identifier) as! FBFuture<AnyObject>
                })
          }
          if uninstallFutures.isEmpty {
            return FBFuture(result: NSNull() as AnyObject)
          }
          return Self.combineFutures(uninstallFutures)
        }) as! FBFuture<NSNull>
  }

  private func debugserver_prepare(_ bundleID: String) -> FBFuture<AnyObject> {
    return FBFuture.onQueue(
      target.workQueue,
      resolve: {
        if self.debugServer != nil {
          return FBControlCoreError.describe("Debug server is already running").failFuture()
        }
        let persisted = self.storageManager.application.persistedBundles
        guard let bundle = persisted[bundleID] else {
          return FBIDBError.describe("\(bundleID) not persisted application and is therefore not debuggable. Suitable applications: \(FBCollectionInformation.oneLineDescription(from: Array(persisted.keys)))").failFuture()
        }
        return FBFuture(result: bundle as AnyObject)
      })
  }

  private func applicationDataContainerCommands(_ containerType: String?) -> FBFutureContext<AnyObject> {
    if containerType == FBFileContainerKind.crashes.rawValue {
      return target.crashLogFiles() as! FBFutureContext<AnyObject>
    }
    guard let commands = target as? FBFileCommands else {
      return FBControlCoreError.describe("Target doesn't conform to FBFileCommands protocol \(target)").failFutureContext()
    }
    if containerType == FBFileContainerKind.application.rawValue {
      return commands.fileCommandsForApplicationContainers() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.group.rawValue {
      return commands.fileCommandsForGroupContainers() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.media.rawValue {
      return commands.fileCommandsForMediaDirectory() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.root.rawValue {
      return commands.fileCommandsForRootFilesystem() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.provisioningProfiles.rawValue {
      return commands.fileCommandsForProvisioningProfiles() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.mdmProfiles.rawValue {
      return commands.fileCommandsForMDMProfiles() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.springboardIcons.rawValue {
      return commands.fileCommandsForSpringboardIconLayout() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.wallpaper.rawValue {
      return commands.fileCommandsForWallpaper() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.diskImages.rawValue {
      return commands.fileCommandsForDiskImages() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.symbols.rawValue {
      return commands.fileCommandsForSymbols() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.auxillary.rawValue {
      return commands.fileCommandsForAuxillary() as! FBFutureContext<AnyObject>
    }
    if containerType == FBFileContainerKind.xctest.rawValue {
      return FBFutureContext(result: storageManager.xctest.asFileContainer() as AnyObject)
    }
    if containerType == FBFileContainerKind.dylib.rawValue {
      return FBFutureContext(result: storageManager.dylib.asFileContainer() as AnyObject)
    }
    if containerType == FBFileContainerKind.dsym.rawValue {
      return FBFutureContext(result: storageManager.dsym.asFileContainer() as AnyObject)
    }
    if containerType == FBFileContainerKind.framework.rawValue {
      return FBFutureContext(result: storageManager.framework.asFileContainer() as AnyObject)
    }
    if containerType == nil || containerType?.isEmpty == true {
      return target is FBDevice ? commands.fileCommandsForMediaDirectory() as! FBFutureContext<AnyObject> : commands.fileCommandsForRootFilesystem() as! FBFutureContext<AnyObject>
    }
    return commands.fileCommands(forContainerApplication: containerType!) as! FBFutureContext<AnyObject>
  }

  private func screenshotCommands() -> FBFuture<AnyObject> {
    let commands = target as FBScreenshotCommands
    return FBFuture(result: commands as AnyObject)
  }

  private func lifecycleCommands() -> FBFuture<AnyObject> {
    guard let commands = target as? FBSimulatorLifecycleCommandsProtocol else {
      return FBIDBError.describe("Target doesn't conform to FBSimulatorLifecycleCommands protocol \(target)").failFuture()
    }
    return FBFuture(result: commands as AnyObject)
  }

  private func mediaCommands() -> FBFuture<AnyObject> {
    guard let commands = target as? FBSimulatorMediaCommandsProtocol else {
      return FBIDBError.describe("Target doesn't conform to FBSimulatorMediaCommands protocol \(target)").failFuture()
    }
    return FBFuture(result: commands as AnyObject)
  }

  private func keychainCommands() -> FBFuture<AnyObject> {
    guard let commands = target as? FBSimulatorKeychainCommandsProtocol else {
      return FBIDBError.describe("Target doesn't conform to FBSimulatorKeychainCommands protocol \(target)").failFuture()
    }
    return FBFuture(result: commands as AnyObject)
  }

  private func settingsCommands() -> FBFuture<AnyObject> {
    guard let commands = target as? (any FBSimulatorSettingsCommandsProtocol) else {
      return FBIDBError.describe("Target doesn't conform to FBSimulatorSettingsCommands protocol \(target)").failFuture()
    }
    return FBFuture(result: commands as AnyObject)
  }

  private func accessibilityCommands() -> FBFuture<AnyObject> {
    guard let commands = target as? FBAccessibilityCommands else {
      return FBIDBError.describe("Target doesn't conform to FBAccessibilityCommands protocol \(target)").failFuture()
    }
    return FBFuture(result: commands as AnyObject)
  }

  private func connectToHID() -> FBFuture<AnyObject> {
    return lifecycleCommands()
      .onQueue(
        target.workQueue,
        fmap: { commands in
          let cmds = commands as! FBSimulatorLifecycleCommandsProtocol
          do {
            try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(self.target.logger)
          } catch {
            return FBFuture(error: error as NSError)
          }
          return cmds.connectToHID() as! FBFuture<AnyObject>
        })
  }

  private func installExtractedApp(_ extractedAppContext: FBFutureContext<AnyObject>, makeDebuggable: Bool) -> FBFuture<FBInstalledArtifact> {
    let bundleContext =
      extractedAppContext
      .onQueue(
        target.asyncQueue,
        pend: { extractPath in
          do {
            let url = extractPath as! URL
            guard let bundleDescriptor = try? FBBundleDescriptor.findAppPath(fromDirectory: url, logger: self.target.logger) else {
              return FBFuture(error: FBControlCoreError.describe("No app bundle could be extracted").build() as NSError)
            }
            return FBFuture(result: bundleDescriptor as AnyObject)
          }
        })
    return installAppBundle(bundleContext, makeDebuggable: makeDebuggable)
  }

  private func installAppBundle(_ bundleContext: FBFutureContext<AnyObject>, makeDebuggable: Bool) -> FBFuture<FBInstalledArtifact> {
    let userDevelopmentAppIsRequired = target is FBDevice

    return
      bundleContext
      .onQueue(
        target.asyncQueue,
        pop: { bundle in
          guard let appBundle = bundle as? FBBundleDescriptor else {
            return FBIDBError.describe("No app bundle could be extracted").failFuture()
          }
          do {
            try self.storageManager.application.checkArchitecture(appBundle)
          } catch {
            return FBFuture(error: error as NSError)
          }
          return self.target.installApplication(withPath: appBundle.path)
            .onQueue(
              self.target.asyncQueue,
              fmap: { installed in
                (self.storageManager.application.saveBundle(appBundle) as! FBFuture<AnyObject>)
                  .onQueue(
                    self.target.asyncQueue,
                    fmap: { _ -> FBFuture<AnyObject> in
                      if makeDebuggable && userDevelopmentAppIsRequired {
                        if installed.installType != .userDevelopment {
                          return FBIDBError.describe("\(appBundle.identifier) is not a user-development signed app and cannot be debugged on this device").failFuture()
                        }
                      }
                      return FBFuture(result: FBInstalledArtifact(name: appBundle.identifier, uuid: appBundle.binary?.uuid as NSUUID?, path: URL(fileURLWithPath: appBundle.path)) as AnyObject)
                    })
              })
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func installXctest(_ extractedXctest: FBFutureContext<AnyObject>, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    return
      extractedXctest
      .onQueue(
        target.workQueue,
        pop: { extractionDirectory in
          let dir = extractionDirectory as! URL
          return self.storageManager.xctest.saveBundleOrTestRunFromBaseDirectory(dir, skipSigningBundles: skipSigningBundles) as! FBFuture<AnyObject>
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func installXctestFilePath(_ bundle: FBFutureContext<AnyObject>, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    return
      bundle
      .onQueue(
        target.workQueue,
        pop: { xctestURL in
          let url = xctestURL as! URL
          return self.storageManager.xctest.saveBundleOrTestRun(url, skipSigningBundles: skipSigningBundles) as! FBFuture<AnyObject>
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func installFile(_ extractedFileContext: FBFutureContext<AnyObject>, intoStorage storage: FBFileStorage) -> FBFuture<FBInstalledArtifact> {
    return
      extractedFileContext
      .onQueue(
        target.workQueue,
        pop: { extractedFile in
          do {
            let url = extractedFile as! URL
            let artifact = try storage.saveFile(url)
            return FBFuture(result: artifact) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func dsymDirnameFromUnzipDir(_ extractedFileContext: FBFutureContext<AnyObject>) -> FBFutureContext<AnyObject> {
    return
      extractedFileContext
      .onQueue(
        target.workQueue,
        pend: { parentDir in
          do {
            let dir = parentDir as! URL
            let subDirs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            if subDirs.count != 1 {
              return FBFuture(result: dir as AnyObject)
            }
            return FBFuture(result: subDirs[0] as AnyObject)
          } catch {
            return FBFuture(error: error as NSError)
          }
        })
  }

  private func installAndLinkDsym(_ extractedFileContext: FBFutureContext<AnyObject>, intoStorage storage: FBFileStorage, linkTo: FBDsymInstallLinkToBundle?) -> FBFuture<FBInstalledArtifact> {
    return
      extractedFileContext
      .onQueue(
        target.workQueue,
        pop: { extractionDir in
          do {
            let dir = extractionDir as! URL
            let artifact = try storage.saveFileInUniquePath(dir)

            guard let linkTo else {
              return FBFuture(result: artifact) as! FBFuture<AnyObject>
            }

            let future: FBFuture<AnyObject>
            if linkTo.bundle_type == .app {
              future =
                self.target.installedApplication(withBundleID: linkTo.bundle_id)
                .onQueue(
                  self.target.workQueue,
                  map: { linkToApp -> AnyObject in
                    let app = linkToApp
                    self.logger.log("Going to create a symlink for app bundle: \(app.bundle.name)")
                    return URL(fileURLWithPath: app.bundle.path) as NSURL
                  })
            } else {
              let testDescriptor = try self.storageManager.xctest.testDescriptor(withID: linkTo.bundle_id)
              self.logger.log("Going to create a symlink for test bundle: \(testDescriptor.name)")
              future = FBFuture(result: testDescriptor.url as AnyObject)
            }

            return
              future
              .onQueue(
                self.target.workQueue,
                fmap: { bundlePath in
                  do {
                    let bundlePathURL = bundlePath as! URL
                    let bundleUrl = bundlePathURL.deletingLastPathComponent()
                    let dsymURL = bundleUrl.appendingPathComponent(artifact.path.lastPathComponent)
                    try? FileManager.default.removeItem(at: dsymURL)
                    self.logger.log("Deleted a symlink for dsym if it already exists: \(dsymURL)")
                    try FileManager.default.createSymbolicLink(at: dsymURL, withDestinationURL: artifact.path)
                    self.logger.log("Created a symlink for dsym from: \(dsymURL) to \(artifact.path)")
                    return FBFuture(result: artifact) as! FBFuture<AnyObject>
                  } catch {
                    return FBFuture(error: error as NSError)
                  }
                })
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<FBInstalledArtifact>
  }

  private func installBundle(_ extractedDirectoryContext: FBFutureContext<AnyObject>, intoStorage storage: FBBundleStorage) -> FBFuture<FBInstalledArtifact> {
    return
      extractedDirectoryContext
      .onQueue(
        target.workQueue,
        pop: { extractedDirectory in
          do {
            let dir = extractedDirectory as! URL
            let bundle = try FBStorageUtils.bundle(inDirectory: dir)
            return storage.saveBundle(bundle) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error as NSError)
          }
        }) as! FBFuture<FBInstalledArtifact>
  }
}
