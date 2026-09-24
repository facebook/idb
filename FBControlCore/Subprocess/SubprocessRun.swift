/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Thrown by the `Subprocess` entrypoints.
public enum SubprocessError: Error, Equatable {
  case unacceptableTermination(status: TerminationStatus, policy: ExitPolicy, executable: String, processIdentifier: pid_t)
  case launchFailed(executable: String, message: String)
  case outputUnavailable(path: String, message: String)
  case timedOut(seconds: TimeInterval, executable: String, processIdentifier: pid_t)
}

extension SubprocessError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .unacceptableTermination(status, _, executable, processIdentifier):
      switch status {
      case .exited(let code):
        return "Process \(processIdentifier) (\(executable)) exited with code \(code), which is not acceptable"
      case .signalled(let signo):
        return "Process \(processIdentifier) (\(executable)) terminated with signal \(signo), which is not acceptable"
      }
    case let .launchFailed(executable, message):
      return "Failed to launch \(executable): \(message)"
    case let .outputUnavailable(path, message):
      return "Cannot create output for \(path): \(message)"
    case let .timedOut(seconds, executable, processIdentifier):
      return "Process \(processIdentifier) (\(executable)) did not terminate within \(seconds) seconds"
    }
  }
}

extension Subprocess {

  /// Launches the process on the host, waits for it to terminate, and
  /// returns its termination status alongside whatever the output captures
  /// produced. Output is fully drained before termination is reported.
  ///
  /// Throws `SubprocessError.unacceptableTermination` when the termination
  /// does not satisfy `exitPolicy` — note that a signal never satisfies a
  /// code-based policy — and `SubprocessError.timedOut` when the process
  /// outlives `timeout`.
  ///
  /// Both cancellation and a timeout stop observation of the process without
  /// killing it, and its exit is still reaped; scoped and escaping lifetimes
  /// are the province of `withRunning` and `launch`. The drains are
  /// deliberately left armed rather than torn down, so an abandoned child goes
  /// on writing to a live pipe instead of taking a SIGPIPE it would never have
  /// seen had the caller waited.
  public func run<Out: Sendable, Err: Sendable>(
    output: Output<Out>,
    error: Output<Err>,
    exitPolicy: ExitPolicy = .mustExitZero,
    timeout: TimeInterval? = nil,
    logger: (any ControlCoreLogger)? = nil
  ) async throws -> Completed<Out, Err> {
    var (stdOut, captureOut) = try output.resolveHost()
    var (stdErr, captureErr): (HostSink, () -> Err)
    do {
      (stdErr, captureErr) = try error.resolveHost()
    } catch let failure {
      stdOut.dispose()
      throw failure
    }

    let running = try await startOnHost(stdOut: &stdOut, stdErr: &stdErr, logger: logger)
    let status: TerminationStatus
    if let timeout {
      guard let resolved = try await running.exit.status(within: timeout) else {
        throw SubprocessError.timedOut(
          seconds: timeout,
          executable: executable,
          processIdentifier: running.processIdentifier)
      }
      status = resolved
    } else {
      status = try await running.exit.status()
    }
    guard exitPolicy.accepts(status) else {
      throw SubprocessError.unacceptableTermination(
        status: status,
        policy: exitPolicy,
        executable: executable,
        processIdentifier: running.processIdentifier)
    }
    return Completed(
      executable: executable,
      processIdentifier: running.processIdentifier,
      terminationStatus: status,
      standardOutput: captureOut(),
      standardError: captureErr())
  }

  /// As `run(output:error:exitPolicy:logger:)`, capturing both streams in
  /// memory as strings — the same default an unconfigured `FBProcessBuilder`
  /// applies, made visible in the return type.
  public func run(
    exitPolicy: ExitPolicy = .mustExitZero,
    timeout: TimeInterval? = nil,
    logger: (any ControlCoreLogger)? = nil
  ) async throws -> Completed<String, String> {
    try await run(output: .string, error: .string, exitPolicy: exitPolicy, timeout: timeout, logger: logger)
  }
}

extension Subprocess.Output {
  static func captured(_ value: Any) -> Captured {
    guard let captured = value as? Captured else {
      preconditionFailure("A \(Captured.self) capture was paired with a sink that produced \(type(of: value)); the factory initializers make this unreachable")
    }
    return captured
  }
}
