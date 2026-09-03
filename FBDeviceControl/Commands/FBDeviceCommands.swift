/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

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
