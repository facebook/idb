/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

/// The captured result of running a tool inside the simulator runtime.
public struct FBInSimulatorToolOutput: Sendable {
  public let stdout: Data
  public let stderr: Data
  public let exitCode: Int32

  public init(stdout: Data, stderr: Data, exitCode: Int32) {
    self.stdout = stdout
    self.stderr = stderr
    self.exitCode = exitCode
  }
}

// MARK: - In-Simulator Tool Spawning

extension FBSimulator {

  /// Runs a tool vendored by the simulator runtime against the booted simulator,
  /// capturing its stdout, stderr and exit code.
  ///
  /// The executable is resolved against the simulator's RuntimeRoot — the
  /// runtime's own build of the tool — not the host's `/usr/bin` copy. This is
  /// load-bearing for the memory tools (`heap`, `vmmap`, `leaks`,
  /// `malloc_history`): the host (macOS) builds link the macOS
  /// `Symbolication.framework`, which cannot walk a simulator process' `dyld_sim`
  /// image list and fails with `Failed to get DYLD info for task ... (os/kern)
  /// failure (5)`. The runtime-vendored builds link the runtime's own
  /// `Symbolication` and can read the target.
  ///
  /// The spawn runs in the CoreSimulator domain via `launchProcess`. Exit codes
  /// are not interpreted here — callers decide which codes are acceptable.
  ///
  /// - Parameters:
  ///   - relativePath: Executable path relative to the RuntimeRoot, e.g.
  ///     `usr/bin/heap` or `bin/sh`.
  ///   - arguments: Arguments passed to the tool.
  ///   - environment: Environment for the spawned tool.
  /// - Returns: The captured stdout, stderr and exit code.
  public func runRuntimeTool(
    _ relativePath: String,
    arguments: [String] = [],
    environment: [String: String] = [:]
  ) async throws -> FBInSimulatorToolOutput {
    let launchPath = try runtimeExecutablePath(relativePath)
    return try await launchProcessConsumingOutput(launchPath: launchPath, arguments: arguments, environment: environment)
  }

  /// Spawns an executable inside the simulator (the CoreSimulator domain, via
  /// `launchProcess`) and captures its stdout, stderr and exit code.
  ///
  /// `launchPath` is used verbatim: `SimDevice` resolves it against the host
  /// filesystem, not the RuntimeRoot. Use `runRuntimeTool` for runtime-vendored
  /// tools; use this directly only for host executables (e.g. `/bin/sh`, which
  /// the runtime does not ship). Exit codes are not interpreted — callers decide
  /// which are acceptable.
  ///
  /// - Parameters:
  ///   - launchPath: Absolute path of the executable.
  ///   - arguments: Arguments passed to the process.
  ///   - environment: Environment for the spawned process.
  /// - Returns: The captured stdout, stderr and exit code.
  public func launchProcessConsumingOutput(
    launchPath: String,
    arguments: [String] = [],
    environment: [String: String] = [:]
  ) async throws -> FBInSimulatorToolOutput {
    let stdoutConsumer = FBDataBuffer.accumulatingBuffer()
    let stderrConsumer = FBDataBuffer.accumulatingBuffer()
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(
      stdIn: nil,
      stdOut: FBProcessOutput<AnyObject>(for: stdoutConsumer),
      stdErr: FBProcessOutput<AnyObject>(for: stderrConsumer)
    )
    let configuration = FBProcessSpawnConfiguration(
      launchPath: launchPath,
      arguments: arguments,
      environment: environment,
      io: io,
      mode: .default
    )

    let process = try await launchProcess(configuration)
    let exitCode = try await bridgeFBFuture(process.exitCode)

    return FBInSimulatorToolOutput(
      stdout: stdoutConsumer.data(),
      stderr: stderrConsumer.data(),
      exitCode: exitCode.int32Value
    )
  }

  /// Resolves an executable vendored by the simulator runtime to its on-disk
  /// path, validating that the binary exists.
  ///
  /// - Parameter relativePath: Path relative to the RuntimeRoot, e.g.
  ///   `usr/bin/heap`.
  private func runtimeExecutablePath(_ relativePath: String) throws -> String {
    guard let root = device.runtime.root else {
      throw FBSimulatorError.describe("Could not obtain runtime root for simulator").build()
    }
    let path = (root as NSString).appendingPathComponent(relativePath)
    let binary = try FBBinaryDescriptor.binary(withPath: path)
    return binary.path
  }
}
