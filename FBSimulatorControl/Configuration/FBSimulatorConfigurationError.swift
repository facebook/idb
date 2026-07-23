/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors thrown while resolving a `FBSimulatorConfiguration` against the runtimes and device types
/// available from CoreSimulator.
///
/// Typed cases let callers pattern-match, while `LocalizedError.errorDescription` preserves the
/// human-readable messages that flow through `error.localizedDescription`. Underlying failures are
/// captured as their localized message rather than the error object, keeping the enum a `Sendable`
/// value type.
public enum FBSimulatorConfigurationError: LocalizedError, Sendable {

  /// No newest OS version is available for the device.
  case noNewestAvailableOS(device: String)

  /// No oldest OS version is available for the device.
  case noOldestAvailableOS(device: String)

  /// The OS version name is not registered with FBSimulatorControl.
  case unsupportedOSVersion(name: String)

  /// The device model is not registered with FBSimulatorControl.
  case unsupportedDevice(name: String)

  /// A matching `SimRuntime` could not be obtained for the configuration.
  case runtimeUnavailable(configuration: String, reason: String?)

  /// A matching `SimDeviceType` could not be obtained for the configuration.
  case deviceTypeUnavailable(configuration: String, reason: String?)

  /// The resolved device type does not support the resolved runtime.
  case runtimeDeviceTypeMismatch(deviceType: String, runtime: String)

  /// No `SimRuntime` matched the configuration's predicate.
  case noMatchingRuntime(available: String)

  /// More than one `SimRuntime` matched the configuration's predicate.
  case ambiguousRuntime(matches: String)

  /// No `SimDeviceType` matched the configuration's predicate.
  case noMatchingDeviceType(available: String)

  /// More than one `SimDeviceType` matched the configuration's predicate.
  case ambiguousDeviceType(matches: String)

  /// The device type backing the default configuration is not registered.
  case noDefaultDeviceTypeRegistered(model: String)

  /// No OS versions are available for the default configuration.
  case noAvailableOSVersionsForDefault

  public var errorDescription: String? {
    switch self {
    case .noNewestAvailableOS(let device):
      return "No newest available OS for device \(device)"
    case .noOldestAvailableOS(let device):
      return "No oldest available OS for device \(device)"
    case .unsupportedOSVersion(let name):
      return "Could not obtain OS Version for \(name), perhaps it is unsupported by FBSimulatorControl"
    case .unsupportedDevice(let name):
      return "Could not obtain Device for \(name), perhaps it is unsupported by FBSimulatorControl"
    case .runtimeUnavailable(let configuration, let reason):
      return Self.describe("Could not obtain available SimRuntime for configuration \(configuration)", reason)
    case .deviceTypeUnavailable(let configuration, let reason):
      return Self.describe("Could not obtain available SimDeviceType for configuration \(configuration)", reason)
    case .runtimeDeviceTypeMismatch(let deviceType, let runtime):
      return "Device Type \(deviceType) does not support Runtime \(runtime)"
    case .noMatchingRuntime(let available):
      return "Could not obtain matching SimRuntime, no matches. Available Runtimes \(available)"
    case .ambiguousRuntime(let matches):
      return "Matching Runtimes is ambiguous: \(matches)"
    case .noMatchingDeviceType(let available):
      return "Could not obtain matching DeviceTypes, no matches. Available Device Types \(available)"
    case .ambiguousDeviceType(let matches):
      return "Matching Device Types is ambiguous: \(matches)"
    case .noDefaultDeviceTypeRegistered(let model):
      return "No device type is registered for '\(model)'"
    case .noAvailableOSVersionsForDefault:
      return "No available OS versions for the default simulator configuration"
    }
  }

  private static func describe(_ base: String, _ reason: String?) -> String {
    guard let reason else { return base }
    return "\(base): \(reason)"
  }
}

extension FBSimulatorConfigurationError: CustomStringConvertible {
  /// Mirrors `errorDescription` so string interpolation (`"\(error)"`) and logs surface the
  /// human-readable message rather than the synthesized case name.
  public var description: String { errorDescription ?? "FBSimulatorConfigurationError" }
}
