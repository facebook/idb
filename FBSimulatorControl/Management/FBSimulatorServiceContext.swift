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

  nonisolated(unsafe) private static var _sharedInstance: FBSimulatorServiceContext?
  private static let sharedLock = NSLock()

  @objc
  public class func sharedServiceContext() -> FBSimulatorServiceContext {
    return sharedServiceContext(withLogger: FBControlCoreGlobalConfiguration.defaultLogger)
  }

  @objc(sharedServiceContextWithLogger:)
  public class func sharedServiceContext(withLogger logger: (any FBControlCoreLogger)?) -> FBSimulatorServiceContext {
    sharedLock.lock()
    defer { sharedLock.unlock() }
    if let instance = _sharedInstance {
      return instance
    }
    let instance = createServiceContext(withLogger: logger)
    _sharedInstance = instance
    return instance
  }

  // MARK: - Private Initialization

  private class func createServiceContext(withLogger logger: (any FBControlCoreLogger)?) -> FBSimulatorServiceContext {
    let serviceContextClass: AnyClass? = NSClassFromString("SimServiceContext")
    assert(
      serviceContextClass != nil && serviceContextClass!.responds(to: NSSelectorFromString("sharedServiceContextForDeveloperDir:error:")),
      "Service Context cannot be instantiated")
    var innerError: AnyObject?
    let serviceContext = (serviceContextClass as! SimServiceContext.Type)
      .sharedServiceContext(forDeveloperDir: FBXcodeConfiguration.developerDirectory, error: &innerError)
    assert(serviceContext != nil, "Could not create a service context with error \(String(describing: innerError))")
    return FBSimulatorServiceContext(serviceContext: serviceContext! as! SimServiceContext)
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
        throw (error as? NSError) ?? FBSimulatorError.describe("Failed to get default device set").build()
      }
      return deviceSet
    }
    let resolvedPath = try FBSimulatorServiceContext.fullyQualifiedDeviceSetPath(deviceSetPath)
    var innerError: AnyObject?
    guard let deviceSet = serviceContext.deviceSet(withPath: resolvedPath, error: &innerError) as? SimDeviceSet else {
      throw
        FBSimulatorError
        .describe("Could not create underlying device set for configuration \(configuration)")
        .caused(by: innerError as? NSError)
        .build()
    }
    return deviceSet
  }

  // MARK: - Private

  private class func fullyQualifiedDeviceSetPath(_ deviceSetPath: String) throws -> String {
    do {
      try FileManager.default.createDirectory(atPath: deviceSetPath, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw
        FBSimulatorError
        .describe("Failed to create custom SimDeviceSet directory at \(deviceSetPath)")
        .caused(by: error as NSError)
        .build()
    }

    // -[NSString stringByResolvingSymlinksInPath] doesn't resolve /var to /private/var.
    // This is important for -[SimServiceContext deviceSetWithPath:error:], which internally caches based on a fully resolved path.
    var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
    guard let result = realpath(deviceSetPath, &pathBuffer) else {
      throw
        FBSimulatorError
        .describe("Failed to get realpath for \(deviceSetPath) '\(String(cString: strerror(errno)))'")
        .build()
    }
    return String(cString: result)
  }
}
