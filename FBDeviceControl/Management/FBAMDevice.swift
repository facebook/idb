/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let UnknownValue = "unknown"

/// The OS name a device class implies, where it implies one.
private let DeviceClassOSPrefixes = [
  "iPhone": "iOS",
  "iPad": "iOS",
]

/// An Object Wrapper around AMDeviceRef.
public final class FBAMDevice: NSObject, FBiOSTargetInfo, FBDeviceCommands {

  // MARK: - Properties

  public let calls: AMDCalls
  public var allValues: [String: Any]
  public let workQueue: DispatchQueue
  public let asyncQueue: DispatchQueue
  public let logger: any FBControlCoreLogger
  // Created eagerly at the end of the initializer: both are constructed with this object, so they
  // cannot be `let` properties, and `lazy` would make first access from two threads a race. The
  // storage is populated before the object is shared, which is what makes the unsynchronised
  // accessors safe.
  private var sessionStorage: FBAMDeviceSession?
  private var serviceManagerStorage: FBAMDeviceServiceManager?

  var session: FBAMDeviceSession {
    guard let sessionStorage else {
      preconditionFailure("The session is created in the initializer")
    }
    return sessionStorage
  }

  var serviceManager: FBAMDeviceServiceManager {
    guard let serviceManagerStorage else {
      preconditionFailure("The service manager is created in the initializer")
    }
    return serviceManagerStorage
  }

  /// Ownership runs through the AMDevice call table rather than ARC, so the setter takes a
  /// reference on the incoming device and drops the one it replaces.
  private var amDeviceReference: AMDevice?

  public var amDeviceRef: AMDevice? {
    get {
      amDeviceReference
    }
    set {
      let old = amDeviceReference
      amDeviceReference = newValue
      if let newValue {
        calls.Retain(newValue)
      }
      if let old {
        calls.Release(old)
      }
    }
  }

  public var amDevice: AMDevice? {
    amDeviceReference
  }

  // MARK: - Initializers

  public init(
    allValues: [String: Any],
    calls: AMDCalls,
    connectionReuseTimeout: NSNumber?,
    serviceReuseTimeout: NSNumber?,
    work workQueue: DispatchQueue,
    asyncQueue: DispatchQueue,
    logger: any FBControlCoreLogger
  ) {
    self.allValues = allValues
    self.calls = calls
    self.workQueue = workQueue
    self.asyncQueue = asyncQueue
    // The udid is read from `allValues`, so the named logger can only be built after it is set.
    let udid = allValues[FBDeviceKey.uniqueDeviceID.rawValue] as? String ?? UnknownValue
    self.logger = logger.withName(udid)
    super.init()
    // The un-named logger: only this object's own logger is decorated with the udid.
    self.sessionStorage = FBAMDeviceSession(
      device: self, reuseTimeout: connectionReuseTimeout?.doubleValue, logger: logger)
    self.serviceManagerStorage = FBAMDeviceServiceManager(
      device: self, serviceTimeout: serviceReuseTimeout?.doubleValue)
  }

  // MARK: - FBiOSTargetInfo

  public var uniqueIdentifier: String {
    // The stored chip identifier may be a number or a string; accepting only a number would
    // silently degrade a string identifier to unknown.
    let value = allValues[FBDeviceKey.uniqueChipID.rawValue]
    if let number = value as? NSNumber {
      return number.stringValue
    }
    if let string = value as? String {
      return string
    }
    return UnknownValue
  }

  public var udid: String {
    allValues[FBDeviceKey.uniqueDeviceID.rawValue] as? String ?? UnknownValue
  }

  public var name: String {
    allValues[FBDeviceKey.deviceName.rawValue] as? String ?? UnknownValue
  }

  public var architectures: [FBArchitecture] {
    guard let architecture = allValues[FBDeviceKey.cpuArchitecture.rawValue] as? String else {
      return []
    }
    return [FBArchitecture(rawValue: architecture)]
  }

  public var deviceType: FBDeviceType {
    let productType = allValues[FBDeviceKey.productType.rawValue] as? String ?? UnknownValue
    return FBiOSTargetConfiguration.productTypeToDevice[productType] ?? FBDeviceType.generic(withName: productType)
  }

  public var osVersion: FBOSVersion {
    let name = Self.osVersionName(
      deviceClass: allValues[FBDeviceKey.deviceClass.rawValue] as? String,
      productVersion: productVersion)
    return FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionName(rawValue: name)] ?? FBOSVersion.generic(withName: name)
  }

  public var state: FBiOSTargetState {
    .booted
  }

  public var targetType: FBiOSTargetType {
    .device
  }

  public var extendedInformation: [String: Any] {
    ["device": FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: allValues)]
  }

  // MARK: - FBDeviceProtocol

  public var buildVersion: String? {
    allValues[FBDeviceKey.buildVersion.rawValue] as? String
  }

  public var productVersion: String? {
    allValues[FBDeviceKey.productVersion.rawValue] as? String
  }

  public var recoveryModeDeviceRef: AMRecoveryModeDevice? {
    nil
  }

  public var activationState: String {
    guard let activationState = allValues[FBDeviceKey.activationState.rawValue] as? String else {
      return FBDeviceActivationState.unknown.rawValue
    }
    return FBDeviceActivationStateCoerceFromString(activationState).rawValue
  }

  // MARK: - FBDeviceCommands

  public func withConnectedDevice<T>(
    purpose: String,
    _ body: (any FBDeviceCommands) async throws -> T
  ) async throws -> T {
    logger.log("Taking the device into use for \(purpose)")
    try await session.acquire()
    defer { session.release() }
    return try await body(self)
  }

  public func startService(_ service: String) -> FBFutureContext<FBAMDServiceConnection> {
    startServiceConnection(service)
  }

  /// Two lifetimes again, and not the ones `withServiceConnection` manages: the AMDevice session
  /// is held for as long as `body` runs, while the AFC connection outlives it. The connection is
  /// pooled for the device's service reuse timeout so a following operation on the same bundle
  /// re-uses it rather than starting house arrest again.
  public func withHouseArrestAFCConnection<T>(
    forBundleID bundleID: String,
    afcCalls: AFCCalls,
    _ body: (FBAFCConnection) async throws -> T
  ) async throws -> T {
    try await withConnectedDevice(purpose: "house_arrest") { _ in
      let service = self.serviceManager.houseArrestService(forBundleID: bundleID, afcCalls: afcCalls)
      let connection = try await service.acquire()
      defer { service.release() }
      return try await body(connection)
    }
  }

  // MARK: - NSObject

  @objc(device:valueForKey:)
  public func device(_ device: AMDevice, valueForKey key: String) -> Any? {
    calls.CopyValue(device, nil, key as CFString)?.takeRetainedValue()
  }

  public override var description: String {
    "AMDevice \(udid) | \(name)"
  }

  // MARK: - Private

  private class func osVersionName(deviceClass: String?, productVersion: String?) -> String {
    guard let productVersion else {
      return UnknownValue
    }
    guard let deviceClass, let osPrefix = DeviceClassOSPrefixes[deviceClass] else {
      return productVersion
    }
    return "\(osPrefix) \(productVersion)"
  }
}
