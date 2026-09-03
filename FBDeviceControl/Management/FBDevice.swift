/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// A class that represents an iOS Device.
///
/// A device is backed by an `FBAMDevice`, an `FBAMRestorableDevice`, or both, and caches the
/// target information of whichever it holds. The AMDevice is the richer source, so its values
/// overwrite; the restorable device only fills gaps.
public final class FBDevice: NSObject, FBiOSTarget, FBDeviceCommands {

  // MARK: - Properties

  public private(set) weak var set: FBDeviceSet?
  public let commandCache: FBTargetCommandCache
  public private(set) var logger: any FBControlCoreLogger
  public private(set) var calls: AMDCalls

  private var amDeviceStorage: FBAMDevice?
  private var restorableDeviceStorage: FBAMRestorableDevice?

  public var amDevice: FBAMDevice? {
    get {
      amDeviceStorage
    }
    set {
      amDeviceStorage = newValue
      if let newValue {
        cacheValues(from: newValue, overwrite: true)
      }
    }
  }

  public var restorableDevice: FBAMRestorableDevice? {
    get {
      restorableDeviceStorage
    }
    set {
      restorableDeviceStorage = newValue
      if let newValue {
        cacheValues(from: newValue, overwrite: false)
      }
    }
  }

  // MARK: - Cached target information

  // Optional storage: the nil state is what `cacheValues(from:overwrite:)` tests to decide
  // whether a gap can be filled. The public accessors are non-optional because the initializer
  // always populates the cache from one of the two backing devices.

  private var cachedUniqueIdentifier: String?
  private var cachedUDID: String?
  private var cachedName: String?
  private var cachedDeviceType: FBDeviceType?
  private var cachedArchitectures: [FBArchitecture]?
  private var cachedOSVersion: FBOSVersion?
  private var cachedExtendedInformation: [String: Any]?
  private var cachedTargetType: FBiOSTargetType?
  private var cachedBuildVersion: String?
  private var cachedProductVersion: String?
  private var cachedActivationState: String?
  private var cachedAllValues: [String: Any]?

  public private(set) var state: FBiOSTargetState = .unknown

  public var uniqueIdentifier: String { cachedUniqueIdentifier ?? "" }
  public var udid: String { cachedUDID ?? "" }
  public var name: String { cachedName ?? "" }
  public var deviceType: FBDeviceType { cachedDeviceType ?? FBDeviceType.generic(withName: "unknown") }
  public var architectures: [FBArchitecture] { cachedArchitectures ?? [] }
  public var osVersion: FBOSVersion { cachedOSVersion ?? FBOSVersion.generic(withName: "unknown") }
  public var extendedInformation: [String: Any] { cachedExtendedInformation ?? [:] }
  public var targetType: FBiOSTargetType { cachedTargetType ?? .none }
  public var buildVersion: String? { cachedBuildVersion }
  public var productVersion: String? { cachedProductVersion }
  public var activationState: String { cachedActivationState ?? "" }
  public var allValues: [String: Any] { cachedAllValues ?? [:] }

  // MARK: - Initializers

  public init(
    set: FBDeviceSet?,
    amDevice: FBAMDevice?,
    restorableDevice: FBAMRestorableDevice?,
    logger: any FBControlCoreLogger
  ) {
    self.set = set
    self.amDeviceStorage = amDevice
    self.restorableDeviceStorage = restorableDevice
    self.commandCache = FBTargetCommandCache()
    // With neither backing device there is no call table, so every later call would dispatch
    // through a null function pointer. Failing here names the cause instead.
    if let amDevice {
      self.calls = amDevice.calls
    } else if let restorableDevice {
      self.calls = restorableDevice.calls
    } else {
      preconditionFailure("An FBAMDevice or FBAMRestorableDevice must be provided")
    }
    self.logger = logger
    super.init()
    if let info: any FBiOSTargetInfo & FBDeviceProtocol = amDevice ?? restorableDevice {
      cacheValues(from: info, overwrite: true)
    }
    self.logger = logger.withName(udid)
  }

  // MARK: - FBiOSTargetCommand

  public static func commands(with target: any FBiOSTarget) -> Self {
    guard let device = target as? Self else {
      preconditionFailure("\(type(of: target)) is not an FBDevice, so it cannot provide device commands")
    }
    return device
  }

  // MARK: - FBiOSTarget

  public var workQueue: DispatchQueue {
    // One of the two backing devices is always present, per the initializer's contract.
    (amDevice?.workQueue ?? restorableDevice?.workQueue) ?? DispatchQueue.main
  }

  public var asyncQueue: DispatchQueue {
    (amDevice?.asyncQueue ?? restorableDevice?.asyncQueue) ?? DispatchQueue.global()
  }

  private var temporaryDirectoryStorage: FBTemporaryDirectory?

  public var temporaryDirectory: FBTemporaryDirectory {
    if let temporaryDirectoryStorage {
      return temporaryDirectoryStorage
    }
    let created = FBTemporaryDirectory(logger: logger)
    temporaryDirectoryStorage = created
    return created
  }

  public var auxillaryDirectory: String {
    let cwd = FileManager.default.currentDirectoryPath
    return FileManager.default.isWritableFile(atPath: cwd) ? cwd : "/tmp"
  }

  public var platformRootDirectory: String {
    (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneOS.platform")
  }

  public var runtimeRootDirectory: String {
    platformRootDirectory
  }

  public var screenInfo: FBiOSTargetScreenInfo? {
    nil
  }

  public var customDeviceSetPath: String? {
    nil
  }

  public func compare(_ target: any FBiOSTarget) -> ComparisonResult {
    FBiOSTargetComparison(self, target)
  }

  public func requiresBundlesToBeSigned() -> Bool {
    true
  }

  public func replacementMapping() -> [String: String] {
    [:]
  }

  public func environmentAdditions() -> [String: String] {
    [:]
  }

  // MARK: - NSObject

  public override var description: String {
    FBiOSTargetDescribe(self)
  }

  // MARK: - FBDeviceProtocol

  public var amDeviceRef: AMDevice? {
    amDevice?.amDeviceRef
  }

  public var recoveryModeDeviceRef: AMRecoveryModeDevice? {
    restorableDevice?.recoveryModeDeviceRef
  }

  // MARK: - FBDeviceCommands

  public func connectToDevice(withPurpose purpose: String) -> FBFutureContext<AnyObject> {
    guard let amDevice else {
      return notAMDeviceBacked(operation: "connectToDeviceWithPurpose:")
    }
    return amDevice.connectToDevice(withPurpose: purpose)
  }

  public func startService(_ service: String) -> FBFutureContext<FBAMDServiceConnection> {
    guard let amDevice else {
      return notAMDeviceBacked(operation: "startService:")
    }
    return amDevice.startService(service)
  }

  public func houseArrestAFCConnection(forBundleID bundleID: String, afcCalls: AFCCalls) -> FBFutureContext<FBAFCConnection> {
    guard let amDevice else {
      return notAMDeviceBacked(operation: "houseArrestAFCConnectionForBundleID:afcCalls:")
    }
    return amDevice.houseArrestAFCConnection(forBundleID: bundleID, afcCalls: afcCalls)
  }

  // MARK: - Forwarding

  /// Selectors this class does not implement are forwarded to the AMDevice, so its surface
  /// remains reachable through the device for runtime-dispatched callers.
  public override func forwardingTarget(for aSelector: Selector?) -> Any? {
    if let aSelector, let amDevice, amDevice.responds(to: aSelector) {
      return amDevice
    }
    return super.forwardingTarget(for: aSelector)
  }

  // MARK: - Private

  private func notAMDeviceBacked<T>(operation: String) -> FBFutureContext<T> {
    FBFuture<T>(error: FBAMDeviceServiceError.notAMDeviceBacked(service: operation) as NSError)
      .onQueue(
        workQueue,
        contextualTeardown: { (_: T, _: FBFutureState) -> FBFuture<NSNull> in
          FBFuture<NSNull>.empty()
        })
  }

  /// The AMDevice's richer information always overwrites; the restorable device's only fills what
  /// is not yet known. `calls` and `state` are refreshed from either.
  private func cacheValues(from targetInfo: any FBiOSTargetInfo & FBDeviceProtocol, overwrite: Bool) {
    calls = targetInfo.calls
    state = targetInfo.state

    if cachedAllValues == nil || overwrite {
      cachedAllValues = targetInfo.allValues
    }
    if cachedArchitectures == nil || overwrite {
      cachedArchitectures = targetInfo.architectures
    }
    if cachedBuildVersion == nil || overwrite {
      cachedBuildVersion = targetInfo.buildVersion
    }
    if cachedDeviceType == nil || overwrite {
      cachedDeviceType = targetInfo.deviceType
    }
    if cachedExtendedInformation == nil || overwrite {
      cachedExtendedInformation = targetInfo.extendedInformation
    }
    if cachedName == nil || overwrite {
      cachedName = targetInfo.name
    }
    if cachedOSVersion == nil || overwrite {
      cachedOSVersion = targetInfo.osVersion
    }
    if cachedProductVersion == nil || overwrite {
      cachedProductVersion = targetInfo.productVersion
    }
    if cachedTargetType == nil || overwrite {
      cachedTargetType = targetInfo.targetType
    }
    if cachedUDID == nil || overwrite {
      cachedUDID = targetInfo.udid
    }
    if cachedUniqueIdentifier == nil || overwrite {
      cachedUniqueIdentifier = targetInfo.uniqueIdentifier
    }
    if cachedActivationState == nil || overwrite {
      cachedActivationState = targetInfo.activationState
    }
  }
}
