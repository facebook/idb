/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors thrown while creating or cloning simulators in an `FBSimulatorSet`.
///
/// Typed cases let callers pattern-match, while `LocalizedError.errorDescription` preserves the
/// human-readable messages that flow through `error.localizedDescription`. Underlying CoreSimulator
/// failures are captured as their localized message, keeping the enum a `Sendable` value type.
public enum FBSimulatorSetError: LocalizedError, Sendable {

  /// The device type or runtime for the requested configuration could not be obtained.
  case deviceTypeOrRuntimeUnavailable(configuration: String, reason: String?)

  /// A freshly-created simulator could not be moved into a shutdown state.
  case shutdownAfterCreateFailed(reason: String?)

  /// A device was created/cloned but no matching simulator was inflated into the set.
  case simulatorNotInflated(udid: String)

  /// CoreSimulator reported neither a device nor an error when creating a device.
  case deviceCreationFailed

  /// CoreSimulator reported neither a device nor an error when cloning a device.
  case deviceCloneFailed

  public var errorDescription: String? {
    switch self {
    case .deviceTypeOrRuntimeUnavailable(let configuration, let reason):
      return Self.describe("Could not obtain DeviceType or SimRuntime for Configuration \(configuration)", reason)
    case .shutdownAfterCreateFailed(let reason):
      return Self.describe("Could not get newly-created simulator into a shutdown state", reason)
    case .simulatorNotInflated(let udid):
      return "Expected simulator with UDID \(udid) to be inflated"
    case .deviceCreationFailed:
      return "Failed to create device with no error"
    case .deviceCloneFailed:
      return "Failed to clone device with no error"
    }
  }

  private static func describe(_ base: String, _ reason: String?) -> String {
    guard let reason else { return base }
    return "\(base): \(reason)"
  }
}

extension FBSimulatorSetError: CustomStringConvertible {
  /// Mirrors `errorDescription` so string interpolation (`"\(error)"`) and logs surface the
  /// human-readable message rather than the synthesized case name.
  public var description: String { errorDescription ?? "FBSimulatorSetError" }
}
