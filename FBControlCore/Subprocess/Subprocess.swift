/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The specification of a process to launch: what to run, with which
/// arguments and environment, and how the launcher should spawn it.
///
/// A `Subprocess` is a plain value. It carries no live process state and no
/// IO configuration — output and input are arguments to the launch call, so
/// their types flow into the result rather than being stored here.
public struct Subprocess: Sendable, Equatable {

  /// The absolute path of the executable to launch.
  public var executable: String

  /// The arguments to pass, excluding the executable itself.
  public var arguments: [String]

  /// The environment the child receives.
  public var environment: Environment

  /// How the process is spawned. Only meaningful to launchers that
  /// distinguish spawn modes; the host launcher ignores it.
  public var mode: LaunchMode

  public init(
    executable: String,
    arguments: [String] = [],
    environment: Environment = .idbDefault,
    mode: LaunchMode = .default
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.mode = mode
  }

  /// The environment a child process receives.
  public enum Environment: Sendable, Equatable {
    /// A minimal allowlist inherited from this process: `DEVELOPER_DIR`,
    /// `HOME` and `PATH`, where set.
    case idbDefault
    /// The full environment of this process.
    case inherit
    /// Exactly these variables and nothing else.
    case exact([String: String])
    /// The `idbDefault` allowlist, overlaid with these variables.
    case additions([String: String])

    /// The variables `idbDefault` passes through from the parent.
    static let idbDefaultKeys = ["DEVELOPER_DIR", "HOME", "PATH"]

    /// The concrete variables the child receives, given the parent's
    /// environment.
    func resolved(against parent: [String: String]) -> [String: String] {
      switch self {
      case .idbDefault:
        return Self.filtered(parent)
      case .inherit:
        return parent
      case .exact(let environment):
        return environment
      case .additions(let additions):
        return Self.filtered(parent).merging(additions) { _, addition in addition }
      }
    }

    private static func filtered(_ parent: [String: String]) -> [String: String] {
      parent.filter { idbDefaultKeys.contains($0.key) }
    }
  }

  /// How a launcher spawns the process. Mirrors `ProcessSpawnMode`.
  public enum LaunchMode: Sendable, Equatable {
    /// The launcher's own default.
    case `default`
    /// Spawn standalone, outside launchd. Simulator-only.
    case posixSpawn
    /// Spawn as a launchd job inside the target. Simulator-only.
    case launchd
  }
}
