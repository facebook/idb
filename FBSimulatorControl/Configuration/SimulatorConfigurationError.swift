/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors thrown while resolving a `FBSimulatorConfiguration` against the runtimes and device types
/// available from CoreSimulator.
public enum FBSimulatorConfigurationError: LocalizedError, Sendable {
  case noNewestAvailableOS(device: String)
  case noOldestAvailableOS(device: String)
  case unsupportedOSVersion(name: String)
  case unsupportedDevice(name: String)
  case runtimeUnavailable(configuration: String, reason: String?)
  case deviceTypeUnavailable(configuration: String, reason: String?)
  case runtimeDeviceTypeMismatch(deviceType: String, runtime: String)
  case noMatchingRuntime(available: String)
  case ambiguousRuntime(matches: String)
  case noMatchingDeviceType(available: String)
  case ambiguousDeviceType(matches: String)
  case noDefaultDeviceTypeRegistered(model: String)
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
