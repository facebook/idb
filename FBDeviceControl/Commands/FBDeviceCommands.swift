/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// The Activation State of the device.
public enum FBDeviceActivationState: String, Sendable, CaseIterable {
  case unknown = "Unknown"
  case unactivated = "Unactivated"
  case activated = "Activated"
}

/// The canonical activation state for whatever the device reported.
public func FBDeviceActivationStateCoerceFromString(_ activationState: String) -> FBDeviceActivationState {
  FBDeviceActivationState(rawValue: activationState) ?? .unknown
}

/// Keys of the device information dictionaries MobileDevice populates.
public enum FBDeviceKey: String, Sendable, CaseIterable {
  case chipID = "ChipID"
  case deviceClass = "DeviceClass"
  case deviceName = "DeviceName"
  case locationID = "LocationID"
  case productType = "ProductType"
  case serialNumber = "SerialNumber"
  case uniqueChipID = "UniqueChipID"
  case uniqueDeviceID = "UniqueDeviceID"
  case cpuArchitecture = "CPUArchitecture"
  case buildVersion = "BuildVersion"
  case productVersion = "ProductVersion"
  case activationState = "ActivationState"
  case isPaired = "IsPaired"
}

/// Defines properties that are required on classes related to the implementation of FBDevice.
public protocol FBDeviceProtocol: AnyObject {

  /// The AMDevice Calls to use.
  var calls: AMDCalls { get }

  /// The underlying AMDeviceRef. This may be nil.
  var amDeviceRef: AMDevice? { get }

  /// The underlying AMRecoveryModeDeviceRef if in recovery. This may be nil.
  var recoveryModeDeviceRef: AMRecoveryModeDevice? { get }

  /// The Device's Logger.
  var logger: any FBControlCoreLogger { get }

  /// The Device's 'Product Version'.
  var productVersion: String? { get }

  /// The Device's 'Build Version'.
  var buildVersion: String? { get }

  /// The Device's 'Activation State'.
  var activationState: String { get }

  /// All of the Device Values available.
  var allValues: [String: Any] { get }
}

/// Defines Device-Specific commands, off which others are based.
public protocol FBDeviceCommands: FBDeviceProtocol {

  /// Obtains the connection for a device, wrapped in an async context.
  func connectToDevice(withPurpose purpose: String) -> FBFutureContext<AnyObject>

  /// Starts a service on the AMDevice.
  func startService(_ service: String) -> FBFutureContext<FBAMDServiceConnection>

  /// Starts house arrest for a given bundle id, with the AFC calls to inject.
  func houseArrestAFCConnection(forBundleID bundleID: String, afcCalls: AFCCalls) -> FBFutureContext<FBAFCConnection>
}

extension FBDeviceCommands {
  /// Connects for the duration of `body`, handing it the typed connected device.
  ///
  /// This is the seam every consumer should use: the raw `connectToDevice` context is erased to
  /// `AnyObject` because Objective-C generics cannot carry a Swift existential, and dynamic
  /// member lookup on `AnyObject` compiles against any `@objc` member and fails at runtime — the
  /// cast here is what turns that silent hazard back into a type error at the call site.
  public func withConnectedDevice<T>(
    purpose: String,
    _ body: (any FBDeviceCommands) async throws -> T
  ) async throws -> T {
    try await withFBFutureContext(connectToDevice(withPurpose: purpose)) { connected in
      guard let connected = connected as? any FBDeviceCommands else {
        throw FBAMDeviceServiceError.notAMDeviceBacked(service: purpose)
      }
      return try await body(connected)
    }
  }
}
