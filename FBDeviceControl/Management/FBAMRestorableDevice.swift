/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let UnknownValue = "unknown"

/// An Object Wrapper around AMRestorableDevice.
@objc(FBAMRestorableDevice)
public final class FBAMRestorableDevice: NSObject, FBiOSTargetInfo, FBDeviceProtocol {

  // MARK: - Properties

  @objc public let calls: AMDCalls
  @objc public var allValues: [String: Any]
  @objc public let workQueue: DispatchQueue
  @objc public let asyncQueue: DispatchQueue
  @objc public let logger: any FBControlCoreLogger

  /// Owns a +1 reference: retained on assignment, released on replacement and in `deinit`.
  private var restorableDeviceRef: Unmanaged<AnyObject>

  @objc public var restorableDevice: AMRestorableDevice {
    get {
      restorableDeviceRef.takeUnretainedValue()
    }
    set {
      let replacement = Unmanaged.passRetained(newValue as AnyObject)
      restorableDeviceRef.release()
      restorableDeviceRef = replacement
    }
  }

  // MARK: - Initializers

  @objc(initWithCalls:restorableDevice:allValues:workQueue:asyncQueue:logger:)
  public init(
    calls: AMDCalls,
    restorableDevice: AMRestorableDevice,
    allValues: [String: Any],
    work workQueue: DispatchQueue,
    asyncQueue: DispatchQueue,
    logger: any FBControlCoreLogger
  ) {
    self.calls = calls
    self.restorableDeviceRef = Unmanaged.passRetained(restorableDevice as AnyObject)
    self.allValues = allValues
    self.workQueue = workQueue
    self.asyncQueue = asyncQueue
    self.logger = logger
    super.init()
  }

  deinit {
    restorableDeviceRef.release()
  }

  // MARK: - FBiOSTargetInfo

  // Restore info dictionaries are populated by MobileDevice and may omit keys or carry
  // unexpectedly-typed values; these accessors feed Swift's nonnull String bridging, so anything
  // unexpected must degrade to the unknown value rather than trap.

  @objc public var uniqueIdentifier: String {
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
    UnknownValue
  }

  @objc public var name: String {
    allValues[FBDeviceKey.deviceName.rawValue] as? String ?? UnknownValue
  }

  @objc public var state: FBiOSTargetState {
    Self.targetState(for: AMRestorableDeviceState(rawValue: calls.RestorableDeviceGetState(restorableDevice)) ?? .unknown)
  }

  @objc public var deviceType: FBDeviceType {
    let productString = allValues[FBDeviceKey.productType.rawValue] as? String ?? UnknownValue
    return FBDeviceType.generic(withName: productString)
  }

  @objc public var architectures: [FBArchitecture] {
    [FBArchitecture(rawValue: UnknownValue)]
  }

  @objc public var targetType: FBiOSTargetType {
    .device
  }

  @objc public var osVersion: FBOSVersion {
    FBOSVersion.generic(withName: UnknownValue)
  }

  @objc public var extendedInformation: [String: Any] {
    ["device": allValues]
  }

  // MARK: - FBDeviceProtocol

  @objc public var buildVersion: String? {
    UnknownValue
  }

  @objc public var productVersion: String? {
    UnknownValue
  }

  @objc public var amDeviceRef: AMDevice? {
    nil
  }

  @objc public var recoveryModeDeviceRef: AMRecoveryModeDevice? {
    calls.RestorableDeviceGetRecoveryModeDevice(restorableDevice)?.takeUnretainedValue()
  }

  /// Typed `NSString` rather than `FBDeviceActivationState`: the protocol declares this property
  /// `assign` on an object type, so the string-enum typedef does not survive into the requirement.
  @objc public var activationState: NSString {
    FBDeviceActivationState.unknown.rawValue as NSString
  }

  // MARK: - Public

  /// `AMRestorableGetStringForState` is private, and the mapping is simple enough to restate.
  @objc(targetStateForDeviceState:)
  public class func targetState(for state: AMRestorableDeviceState) -> FBiOSTargetState {
    switch state {
    case .DFU:
      return .DFU
    case .recovery:
      return .recovery
    case .restoreOS:
      return .restoreOS
    case .bootedOS:
      return .booted
    case .unknown:
      return .unknown
    @unknown default:
      return .unknown
    }
  }
}
