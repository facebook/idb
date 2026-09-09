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
public final class FBAMRestorableDevice: FBiOSTargetInfo, FBDeviceProtocol {

  public let calls: AMDCalls
  public var allValues: [String: Any]
  public let workQueue: DispatchQueue
  public let asyncQueue: DispatchQueue
  public let logger: any FBControlCoreLogger

  /// Owns a +1 reference: retained on assignment, released on replacement and in `deinit`.
  private var restorableDeviceRef: Unmanaged<AnyObject>

  var restorableDevice: AMRestorableDevice {
    get {
      restorableDeviceRef.takeUnretainedValue()
    }
    set {
      let replacement = Unmanaged.passRetained(newValue as AnyObject)
      restorableDeviceRef.release()
      restorableDeviceRef = replacement
    }
  }

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
  }

  deinit {
    restorableDeviceRef.release()
  }

  // MARK: - FBiOSTargetInfo

  // Restore info dictionaries are populated by MobileDevice and may omit keys or carry
  // unexpectedly-typed values; these accessors feed Swift's nonnull String bridging, so anything
  // unexpected must degrade to the unknown value rather than trap.

  public var uniqueIdentifier: String {
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
    UnknownValue
  }

  public var name: String {
    allValues[FBDeviceKey.deviceName.rawValue] as? String ?? UnknownValue
  }

  public var state: FBiOSTargetState {
    Self.targetState(for: AMRestorableDeviceState(rawValue: calls.RestorableDeviceGetState(restorableDevice)) ?? .unknown)
  }

  public var deviceType: FBDeviceType {
    let productString = allValues[FBDeviceKey.productType.rawValue] as? String ?? UnknownValue
    return FBDeviceType.generic(withName: productString)
  }

  public var architectures: [FBArchitecture] {
    [FBArchitecture(rawValue: UnknownValue)]
  }

  public var targetType: FBiOSTargetType {
    .device
  }

  public var osVersion: FBOSVersion {
    FBOSVersion.generic(withName: UnknownValue)
  }

  public var extendedInformation: [String: Any] {
    ["device": allValues]
  }

  // MARK: - FBDeviceProtocol

  public var buildVersion: String? {
    UnknownValue
  }

  public var productVersion: String? {
    UnknownValue
  }

  public var amDeviceRef: AMDevice? {
    nil
  }

  public var recoveryModeDeviceRef: AMRecoveryModeDevice? {
    calls.RestorableDeviceGetRecoveryModeDevice(restorableDevice)?.takeUnretainedValue()
  }

  public var activationState: String {
    FBDeviceActivationState.unknown.rawValue
  }

  /// `AMRestorableGetStringForState` is private, and the mapping is simple enough to restate.
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
