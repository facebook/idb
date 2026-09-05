/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors thrown while creating or cloning simulators in an `FBSimulatorSet`.
public enum FBSimulatorSetError: LocalizedError, Sendable {
  case deviceTypeOrRuntimeUnavailable(configuration: String, reason: String?)
  case shutdownAfterCreateFailed(reason: String?)
  case simulatorNotInflated(udid: String)
  case simulatorHasNoSet(udid: String)
  case deviceCreationFailed
  case deviceCloneFailed

  public var errorDescription: String? {
    switch self {
    case .deviceTypeOrRuntimeUnavailable(let configuration, let reason):
      return Self.describe("Could not obtain DeviceType or SimRuntime for Configuration \(configuration)", reason)
    case .shutdownAfterCreateFailed(let reason):
      return Self.describe("Could not get newly-created simulator into a shutdown state", reason)
    case .simulatorNotInflated(let udid):
      return "Expected simulator with UDID \(udid) to be inflated"
    case .simulatorHasNoSet(let udid):
      return "Simulator with UDID \(udid) does not belong to a simulator set"
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
