/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors resolving a creation request against available CoreSimulator device/runtime pairs.
public enum SimulatorConfigurationError: LocalizedError, Sendable {
  case noMatchingRuntime(available: String)
  case noMatchingDeviceType(available: String)
  case ambiguousDeviceType(matches: String)

  public var errorDescription: String? {
    switch self {
    case .noMatchingRuntime(let available):
      return "Could not obtain matching SimRuntime, no matches. Available Runtimes \(available)"
    case .noMatchingDeviceType(let available):
      return "Could not obtain matching DeviceTypes, no matches. Available Device Types \(available)"
    case .ambiguousDeviceType(let matches):
      return "Matching Device Types is ambiguous: \(matches)"
    }
  }
}

extension SimulatorConfigurationError: CustomStringConvertible {
  /// Mirrors `errorDescription` so string interpolation (`"\(error)"`) and logs surface the
  /// human-readable message rather than the synthesized case name.
  public var description: String { errorDescription ?? "SimulatorConfigurationError" }
}
