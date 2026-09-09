/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

public final class SimulatorServiceContext {

  private let serviceContext: SimServiceContext

  // MARK: - Initialization

  nonisolated(unsafe) private static var _sharedInstance: SimulatorServiceContext?
  private static let sharedLock = NSLock()

  public class func sharedServiceContext() throws -> SimulatorServiceContext {
    return try sharedServiceContext(withLogger: FBControlCoreGlobalConfiguration.defaultLogger)
  }

  public class func sharedServiceContext(withLogger logger: (any FBControlCoreLogger)?) throws -> SimulatorServiceContext {
    sharedLock.lock()
    defer { sharedLock.unlock() }
    if let instance = _sharedInstance {
      return instance
    }
    let instance = try createServiceContext(withLogger: logger)
    _sharedInstance = instance
    return instance
  }

  // MARK: - Private Initialization

  private class func createServiceContext(withLogger logger: (any FBControlCoreLogger)?) throws -> SimulatorServiceContext {
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
    guard
      let serviceContextClass = NSClassFromString("SimServiceContext") as? SimServiceContext.Type,
      serviceContextClass.responds(to: NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"))
    else {
      throw SimulatorServiceContextError.serviceContextClassUnavailable
    }
    // An empty developer directory makes -[SimServiceContext sharedServiceContextForDeveloperDir:error:]
    // crash with an opaque NSException; throw a clear error instead.
    let developerDirectory = FBXcodeConfiguration.developerDirectory
    guard !developerDirectory.isEmpty else {
      throw SimulatorServiceContextError.noFullXcodeSelected
    }

    var innerError: AnyObject?
    let serviceContext =
      serviceContextClass
      .sharedServiceContext(forDeveloperDir: developerDirectory, error: &innerError)
    guard let serviceContext = serviceContext as? SimServiceContext else {
      throw SimulatorServiceContextError.serviceContextUnavailable(
        developerDirectory: developerDirectory,
        reason: (innerError as? NSError)?.localizedDescription)
    }
    return SimulatorServiceContext(serviceContext: serviceContext)
  }

  private init(serviceContext: SimServiceContext) {
    self.serviceContext = serviceContext
  }

  func pathsOfAllDeviceSets() -> [String] {
    var deviceSetPaths: [String] = []
    if let deviceSets = serviceContext.allDeviceSets() as? [SimDeviceSet] {
      for deviceSet in deviceSets {
        deviceSetPaths.append(deviceSet.setPath)
      }
    }
    return deviceSetPaths
  }

  public func supportedRuntimes() -> [SimRuntime] {
    return (serviceContext.supportedRuntimes as? [SimRuntime]) ?? []
  }

  public func supportedDeviceTypes() -> [SimDeviceType] {
    return (serviceContext.supportedDeviceTypes as? [SimDeviceType]) ?? []
  }

  func createDeviceSet(with configuration: FBSimulatorControlConfiguration) throws -> SimDeviceSet {
    guard let deviceSetPath = configuration.deviceSetPath else {
      // defaultDeviceSetWithError: takes (id *) not (NSError **), so use the raw API
      var error: AnyObject?
      guard let deviceSet = serviceContext.defaultDeviceSetWithError(&error) as? SimDeviceSet else {
        throw SimulatorServiceContextError.defaultDeviceSetUnavailable(reason: (error as? NSError)?.localizedDescription)
      }
      return deviceSet
    }
    let resolvedPath = try SimulatorServiceContext.fullyQualifiedDeviceSetPath(deviceSetPath)
    var innerError: AnyObject?
    guard let deviceSet = serviceContext.deviceSet(withPath: resolvedPath, error: &innerError) as? SimDeviceSet else {
      throw SimulatorServiceContextError.deviceSetUnavailable(
        configuration: "\(configuration)",
        reason: (innerError as? NSError)?.localizedDescription)
    }
    return deviceSet
  }

  private class func fullyQualifiedDeviceSetPath(_ deviceSetPath: String) throws -> String {
    do {
      try FileManager.default.createDirectory(atPath: deviceSetPath, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw SimulatorServiceContextError.deviceSetDirectoryCreationFailed(
        path: deviceSetPath,
        reason: error.localizedDescription)
    }

    // -[NSString stringByResolvingSymlinksInPath] doesn't resolve /var to /private/var.
    // This is important for -[SimServiceContext deviceSetWithPath:error:], which internally caches based on a fully resolved path.
    var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
    guard let result = realpath(deviceSetPath, &pathBuffer) else {
      throw SimulatorServiceContextError.deviceSetPathResolutionFailed(
        path: deviceSetPath,
        reason: String(cString: strerror(errno)))
    }
    return String(cString: result)
  }
}
