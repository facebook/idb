/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors thrown while resolving the CoreSimulator `SimServiceContext` and its device sets.
///
/// Typed cases let callers pattern-match, while `LocalizedError.errorDescription` preserves the
/// human-readable messages that flow through `error.localizedDescription` (sime2e output, logs).
/// Underlying CoreSimulator/`FileManager` failures are captured as their localized message rather
/// than the error object itself, keeping the enum a `Sendable` value type.
public enum FBSimulatorServiceContextError: LocalizedError, Sendable {

  /// No full Xcode is selected, so `FBXcodeConfiguration.developerDirectory` is empty. Resolving a
  /// `SimServiceContext` against an empty developer directory crashes CoreSimulator with an opaque
  /// `NSException`, so this is thrown up-front instead.
  case noFullXcodeSelected

  /// `+[SimServiceContext sharedServiceContextForDeveloperDir:error:]` did not return a context.
  case serviceContextUnavailable(developerDirectory: String, reason: String?)

  /// The default device set could not be resolved from the service context.
  case defaultDeviceSetUnavailable(reason: String?)

  /// A device set could not be created for the given control configuration.
  case deviceSetUnavailable(configuration: String, reason: String?)

  /// The custom device-set directory could not be created on disk.
  case deviceSetDirectoryCreationFailed(path: String, reason: String)

  /// `realpath(3)` failed to resolve the custom device-set path.
  case deviceSetPathResolutionFailed(path: String, reason: String)

  public var errorDescription: String? {
    switch self {
    case .noFullXcodeSelected:
      return "No full Xcode developer directory is selected. Select one with `xcode-select -s` or set DEVELOPER_DIR."
    case .serviceContextUnavailable(let developerDirectory, let reason):
      return Self.describe("Could not create a SimServiceContext for developer directory '\(developerDirectory)'", reason)
    case .defaultDeviceSetUnavailable(let reason):
      return Self.describe("Failed to get default device set", reason)
    case .deviceSetUnavailable(let configuration, let reason):
      return Self.describe("Could not create underlying device set for configuration \(configuration)", reason)
    case .deviceSetDirectoryCreationFailed(let path, let reason):
      return "Failed to create custom SimDeviceSet directory at \(path): \(reason)"
    case .deviceSetPathResolutionFailed(let path, let reason):
      return "Failed to get realpath for \(path) '\(reason)'"
    }
  }

  private static func describe(_ base: String, _ reason: String?) -> String {
    guard let reason else { return base }
    return "\(base): \(reason)"
  }
}

extension FBSimulatorServiceContextError: CustomStringConvertible {
  /// Mirrors `errorDescription` so string interpolation (`"\(error)"`) and logs surface the
  /// human-readable message rather than the synthesized case name.
  public var description: String { errorDescription ?? "FBSimulatorServiceContextError" }
}
