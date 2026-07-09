/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorServiceContext)
public final class FBSimulatorServiceContext: NSObject {

  // MARK: - Properties

  private let serviceContext: SimServiceContext

  // MARK: - Initialization

  // Fork change: CoreSimulator's `sharedServiceContextForDeveloperDir:` vends one
  // context per developer directory. Cache per directory (instead of a single
  // process-lifetime instance) so hosts that switch Xcode at runtime get a
  // context for the newly selected developer directory without a restart.
  nonisolated(unsafe) private static var sharedInstances: [String: FBSimulatorServiceContext] = [:]
  private static let sharedLock = NSLock()

  @objc
  public class func sharedServiceContext() throws -> FBSimulatorServiceContext {
    return try sharedServiceContext(withLogger: FBControlCoreGlobalConfiguration.defaultLogger)
  }

  @objc(sharedServiceContextWithLogger:error:)
  public class func sharedServiceContext(withLogger logger: (any FBControlCoreLogger)?) throws -> FBSimulatorServiceContext {
    let developerDirectory = FBXcodeConfiguration.getDeveloperDirectoryIfExists() ?? ""
    sharedLock.lock()
    defer { sharedLock.unlock() }
    if let instance = sharedInstances[developerDirectory] {
      return instance
    }
    let instance = try createServiceContext(withLogger: logger)
    sharedInstances[developerDirectory] = instance
    return instance
  }

  // MARK: - Private Initialization

  private class func createServiceContext(withLogger logger: (any FBControlCoreLogger)?) throws -> FBSimulatorServiceContext {
    let serviceContextClass: AnyClass? = NSClassFromString("SimServiceContext")
    assert(
      serviceContextClass != nil && serviceContextClass!.responds(to: NSSelectorFromString("sharedServiceContextForDeveloperDir:error:")),
      "Service Context cannot be instantiated")
    // An empty developer directory makes -[SimServiceContext sharedServiceContextForDeveloperDir:error:]
    // crash with an opaque NSException; throw a clear error instead.
    let developerDirectory = FBXcodeConfiguration.developerDirectory
    guard !developerDirectory.isEmpty else {
      throw FBSimulatorServiceContextError.noFullXcodeSelected
    }

    var innerError: AnyObject?
    let serviceContext = (serviceContextClass as! SimServiceContext.Type)
      .sharedServiceContext(forDeveloperDir: developerDirectory, error: &innerError)
    guard let serviceContext = serviceContext as? SimServiceContext else {
      throw FBSimulatorServiceContextError.serviceContextUnavailable(
        developerDirectory: developerDirectory,
        reason: (innerError as? NSError)?.localizedDescription)
    }
    return FBSimulatorServiceContext(serviceContext: serviceContext)
  }

  private init(serviceContext: SimServiceContext) {
    self.serviceContext = serviceContext
    super.init()
  }

  // MARK: - Public

  @objc
  public func pathsOfAllDeviceSets() -> [String] {
    var deviceSetPaths: [String] = []
    if let deviceSets = serviceContext.allDeviceSets() as? [SimDeviceSet] {
      for deviceSet in deviceSets {
        deviceSetPaths.append(deviceSet.setPath)
      }
    }
    return deviceSetPaths
  }

  @objc
  public func supportedRuntimes() -> [SimRuntime] {
    return (serviceContext.supportedRuntimes as? [SimRuntime]) ?? []
  }

  @objc
  public func supportedDeviceTypes() -> [SimDeviceType] {
    return (serviceContext.supportedDeviceTypes as? [SimDeviceType]) ?? []
  }

  @objc(createDeviceSetWithConfiguration:error:)
  public func createDeviceSet(with configuration: FBSimulatorControlConfiguration) throws -> SimDeviceSet {
    guard let deviceSetPath = configuration.deviceSetPath else {
      // defaultDeviceSetWithError: takes (id *) not (NSError **), so use the raw API
      var error: AnyObject?
      guard let deviceSet = serviceContext.defaultDeviceSetWithError(&error) as? SimDeviceSet else {
        throw FBSimulatorServiceContextError.defaultDeviceSetUnavailable(reason: (error as? NSError)?.localizedDescription)
      }
      return deviceSet
    }
    let resolvedPath = try FBSimulatorServiceContext.fullyQualifiedDeviceSetPath(deviceSetPath)
    var innerError: AnyObject?
    guard let deviceSet = serviceContext.deviceSet(withPath: resolvedPath, error: &innerError) as? SimDeviceSet else {
      throw FBSimulatorServiceContextError.deviceSetUnavailable(
        configuration: "\(configuration)",
        reason: (innerError as? NSError)?.localizedDescription)
    }
    return deviceSet
  }

  // MARK: - Private

  private class func fullyQualifiedDeviceSetPath(_ deviceSetPath: String) throws -> String {
    do {
      try FileManager.default.createDirectory(atPath: deviceSetPath, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw FBSimulatorServiceContextError.deviceSetDirectoryCreationFailed(
        path: deviceSetPath,
        reason: error.localizedDescription)
    }

    // -[NSString stringByResolvingSymlinksInPath] doesn't resolve /var to /private/var.
    // This is important for -[SimServiceContext deviceSetWithPath:error:], which internally caches based on a fully resolved path.
    var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
    guard let result = realpath(deviceSetPath, &pathBuffer) else {
      throw FBSimulatorServiceContextError.deviceSetPathResolutionFailed(
        path: deviceSetPath,
        reason: String(cString: strerror(errno)))
    }
    return String(cString: result)
  }
}
