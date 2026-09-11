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
public final class FBAMDevice: FBiOSTargetInfo, DeviceCommands, CustomStringConvertible {

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
  private var sessionStorage: AMDeviceSession?
  private var serviceManagerStorage: AMDeviceServiceManager?

  var session: AMDeviceSession {
    guard let sessionStorage else {
      preconditionFailure("The session is created in the initializer")
    }
    return sessionStorage
  }

  var serviceManager: AMDeviceServiceManager {
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
    let udid = allValues[DeviceKey.uniqueDeviceID.rawValue] as? String ?? UnknownValue
    self.logger = logger.withName(udid)
    // The un-named logger: only this object's own logger is decorated with the udid.
    self.sessionStorage = AMDeviceSession(
      device: self, reuseTimeout: connectionReuseTimeout?.doubleValue, logger: logger)
    self.serviceManagerStorage = AMDeviceServiceManager(
      device: self, serviceTimeout: serviceReuseTimeout?.doubleValue)
  }

  // MARK: - FBiOSTargetInfo

  public var uniqueIdentifier: String {
    // The chip identifier arrives as a number on some devices and a string on others.
    let value = allValues[DeviceKey.uniqueChipID.rawValue]
    if let number = value as? NSNumber {
      return number.stringValue
    }
    if let string = value as? String {
      return string
    }
    return UnknownValue
  }

  public var udid: String {
    allValues[DeviceKey.uniqueDeviceID.rawValue] as? String ?? UnknownValue
  }

  public var name: String {
    allValues[DeviceKey.deviceName.rawValue] as? String ?? UnknownValue
  }

  public var architectures: [FBArchitecture] {
    guard let architecture = allValues[DeviceKey.cpuArchitecture.rawValue] as? String else {
      return []
    }
    return [FBArchitecture(rawValue: architecture)]
  }

  public var deviceType: FBDeviceType {
    let productType = allValues[DeviceKey.productType.rawValue] as? String ?? UnknownValue
    return FBiOSTargetConfiguration.productTypeToDevice[productType] ?? FBDeviceType.generic(withName: productType)
  }

  public var osVersion: FBOSVersion {
    let name = Self.osVersionName(
      deviceClass: allValues[DeviceKey.deviceClass.rawValue] as? String,
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

  // MARK: - DeviceProtocol

  public var buildVersion: String? {
    allValues[DeviceKey.buildVersion.rawValue] as? String
  }

  public var productVersion: String? {
    allValues[DeviceKey.productVersion.rawValue] as? String
  }

  public var recoveryModeDeviceRef: AMRecoveryModeDevice? {
    nil
  }

  public var activationState: String {
    guard let activationState = allValues[DeviceKey.activationState.rawValue] as? String else {
      return DeviceActivationState.unknown.rawValue
    }
    return FBDeviceActivationStateCoerceFromString(activationState).rawValue
  }

  // MARK: - DeviceCommands

  public func withConnectedDevice<T>(
    purpose: String,
    _ body: (any DeviceCommands) async throws -> T
  ) async throws -> T {
    logger.log("Taking the device into use for \(purpose)")
    try await session.acquire()
    defer { session.release() }
    return try await body(self)
  }

  /// The AMDevice session is held only while `body` runs; the AFC connection outlives it, pooled
  /// for the device's service reuse timeout so a following operation on the same bundle re-uses it.
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

  public var description: String {
    "AMDevice \(udid) | \(name)"
  }

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
