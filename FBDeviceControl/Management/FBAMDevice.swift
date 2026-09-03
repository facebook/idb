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
@objc(FBAMDevice)
public final class FBAMDevice: NSObject, FBiOSTargetInfo, FBDeviceCommands, FBFutureContextManagerDelegate {

  // MARK: - Properties

  @objc public let calls: AMDCalls
  @objc public var allValues: [String: Any]
  @objc public let workQueue: DispatchQueue
  @objc public let asyncQueue: DispatchQueue
  @objc public let logger: any FBControlCoreLogger
  @objc public let contextPoolTimeout: NSNumber?
  // Created eagerly at the end of the initializer: both managers take this object as their
  // delegate, so they cannot be `let` properties, and `lazy` would make first access from two
  // threads a race. The storage is populated before the object is shared, which is what makes
  // the unsynchronised accessors safe.
  private var connectionContextManagerStorage: FBFutureContextManager<FBAMDevice>?
  private var serviceManagerStorage: FBAMDeviceServiceManager?

  @objc public var connectionContextManager: FBFutureContextManager<FBAMDevice> {
    guard let connectionContextManagerStorage else {
      preconditionFailure("The connection context manager is created in the initializer")
    }
    return connectionContextManagerStorage
  }

  @objc public var serviceManager: FBAMDeviceServiceManager {
    guard let serviceManagerStorage else {
      preconditionFailure("The service manager is created in the initializer")
    }
    return serviceManagerStorage
  }

  /// Ownership runs through the AMDevice call table rather than ARC, so the setter takes a
  /// reference on the incoming device and drops the one it replaces.
  private var amDeviceReference: AMDevice?

  @objc public var amDeviceRef: AMDevice? {
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

  @objc public var amDevice: AMDevice? {
    amDeviceReference
  }

  // MARK: - Initializers

  @objc(initWithAllValues:calls:connectionReuseTimeout:serviceReuseTimeout:workQueue:asyncQueue:logger:)
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
    self.contextPoolTimeout = connectionReuseTimeout
    // The udid is read from `allValues`, so the named logger can only be built after it is set.
    let udid = allValues[FBDeviceKey.uniqueDeviceID.rawValue] as? String ?? UnknownValue
    self.logger = logger.withName(udid)
    super.init()
    // The un-named logger: only this object's own logger is decorated with the udid.
    self.connectionContextManagerStorage = FBFutureContextManager<FBAMDevice>(
      queue: workQueue, delegate: self, logger: logger)
    self.serviceManagerStorage = FBAMDeviceServiceManager.manager(
      withAMDevice: self, serviceTimeout: serviceReuseTimeout)
  }

  // MARK: - FBiOSTargetInfo

  @objc public var uniqueIdentifier: String {
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

  @objc public var udid: String {
    allValues[FBDeviceKey.uniqueDeviceID.rawValue] as? String ?? UnknownValue
  }

  @objc public var name: String {
    allValues[FBDeviceKey.deviceName.rawValue] as? String ?? UnknownValue
  }

  @objc public var architectures: [FBArchitecture] {
    guard let architecture = allValues[FBDeviceKey.cpuArchitecture.rawValue] as? String else {
      return []
    }
    return [FBArchitecture(rawValue: architecture)]
  }

  @objc public var deviceType: FBDeviceType {
    let productType = allValues[FBDeviceKey.productType.rawValue] as? String ?? UnknownValue
    return FBiOSTargetConfiguration.productTypeToDevice[productType] ?? FBDeviceType.generic(withName: productType)
  }

  @objc public var osVersion: FBOSVersion {
    let name = Self.osVersionName(
      deviceClass: allValues[FBDeviceKey.deviceClass.rawValue] as? String,
      productVersion: productVersion)
    return FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionName(rawValue: name)] ?? FBOSVersion.generic(withName: name)
  }

  @objc public var state: FBiOSTargetState {
    .booted
  }

  @objc public var targetType: FBiOSTargetType {
    .device
  }

  @objc public var extendedInformation: [String: Any] {
    ["device": FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: allValues)]
  }

  // MARK: - FBDeviceProtocol

  @objc public var buildVersion: String? {
    allValues[FBDeviceKey.buildVersion.rawValue] as? String
  }

  @objc public var productVersion: String? {
    allValues[FBDeviceKey.productVersion.rawValue] as? String
  }

  @objc public var recoveryModeDeviceRef: AMRecoveryModeDevice? {
    nil
  }

  @objc public var activationState: String {
    guard let activationState = allValues[FBDeviceKey.activationState.rawValue] as? String else {
      return FBDeviceActivationState.unknown.rawValue
    }
    return FBDeviceActivationStateCoerceFromString(activationState).rawValue
  }

  // MARK: - FBDeviceCommands

  // The protocol witnesses below carry the erased types the requirements import with —
  // `any FBDeviceCommands`, `AnyObject`, `Any` — because a Swift witness must match its
  // requirement exactly rather than covariantly.

  @objc(connectToDeviceWithPurpose:)
  public func connectToDevice(withPurpose purpose: String) -> FBFutureContext<any FBDeviceCommands> {
    connectionContextManager.utilize(withPurpose: purpose).retyped(FBFutureContext<any FBDeviceCommands>.self)
  }

  @objc(startService:)
  public func startService(_ service: String) -> FBFutureContext<FBAMDServiceConnection> {
    startServiceConnection(service)
  }

  @objc(houseArrestAFCConnectionForBundleID:afcCalls:)
  public func houseArrestAFCConnection(forBundleID bundleID: String, afcCalls: AFCCalls) -> FBFutureContext<FBAFCConnection> {
    connectToDevice(withPurpose: "house_arrest")
      .onQueue(
        workQueue,
        replace: { [self] (_: any FBDeviceCommands) -> FBFutureContext<AnyObject> in
          serviceManager
            .houseArrestAFCConnection(forBundleID: bundleID, afcCalls: afcCalls)
            .utilize(withPurpose: udid)
            .retyped(FBFutureContext<AnyObject>.self)
        }
      ).retyped(FBFutureContext<FBAFCConnection>.self)
  }

  // MARK: - FBFutureContextManagerDelegate

  @objc public func prepare(_ logger: any FBControlCoreLogger) -> FBFuture<AnyObject> {
    do {
      guard let amDevice else {
        throw FBAMDeviceServiceError.deviceNotConnected(service: "connect")
      }
      try FBAMDeviceUsage.start(using: amDevice, calls: calls, logger: logger)
    } catch {
      return FBFuture<AnyObject>(error: error as NSError)
    }
    return FBFuture<AnyObject>(result: self)
  }

  @objc public func teardown(_ device: Any, logger: any FBControlCoreLogger) -> FBFuture<NSNull> {
    do {
      guard let amDevice else {
        throw FBAMDeviceServiceError.deviceNotConnected(service: "disconnect")
      }
      try FBAMDeviceUsage.stop(using: amDevice, calls: calls, logger: logger)
    } catch {
      return FBFuture<NSNull>(error: error as NSError)
    }
    return FBFuture<NSNull>.empty()
  }

  @objc public var contextName: String {
    "\(udid)_connection"
  }

  @objc public var isContextSharable: Bool {
    true
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
