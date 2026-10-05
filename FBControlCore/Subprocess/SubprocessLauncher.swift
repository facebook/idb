/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where a `Subprocess` runs: spawns it and reports its exit.
///
/// A launcher does nothing else. Resolving captures, draining output before
/// termination is reported, exit policies and signalling belong to the
/// `Subprocess` entrypoints, so every launcher gets them identically.
public protocol SubprocessLauncher: Sendable {

  /// Whether the spawned process can be given a standard input. When false,
  /// any input other than `.closed` is rejected before anything is opened or
  /// spawned.
  var supportsStandardInput: Bool { get }

  /// Spawns `subprocess` with each descriptor duplicated onto the matching
  /// stream of the child; nil leaves that stream closed. The caller closes
  /// its own copies once this returns.
  func spawn(
    _ subprocess: Subprocess,
    standardInput: Int32?,
    standardOutput: Int32?,
    standardError: Int32?,
    logger: (any ControlCoreLogger)?
  ) async throws -> LaunchedProcess
}

/// A process a launcher has spawned.
public struct LaunchedProcess: Sendable {

  public let processIdentifier: pid_t

  /// Resolves once, with the raw `wait(2)` status word, when the process has
  /// terminated and been reaped. Called exactly once per launch.
  let exitStatLoc: @Sendable () async -> Int32

  public init(processIdentifier: pid_t, exitStatLoc: @escaping @Sendable () async -> Int32) {
    self.processIdentifier = processIdentifier
    self.exitStatLoc = exitStatLoc
  }
}

/// Spawns on this host with `posix_spawn`.
public struct HostSubprocessLauncher: SubprocessLauncher {

  public init() {}

  public var supportsStandardInput: Bool {
    true
  }

  public func spawn(
    _ subprocess: Subprocess,
    standardInput: Int32?,
    standardOutput: Int32?,
    standardError: Int32?,
    logger: (any ControlCoreLogger)?
  ) async throws -> LaunchedProcess {
    let processIdentifier = try HostSubprocess.spawn(
      executable: subprocess.executable,
      arguments: subprocess.arguments,
      environment: subprocess.environment.resolved(against: ProcessInfo.processInfo.environment),
      standardInput: standardInput,
      standardOutput: standardOutput,
      standardError: standardError)
    return LaunchedProcess(processIdentifier: processIdentifier) {
      await HostSubprocess.exitStatLoc(of: processIdentifier, logger: logger)
    }
  }
}
