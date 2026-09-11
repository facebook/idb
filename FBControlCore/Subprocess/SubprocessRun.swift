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
}

extension SubprocessError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .unacceptableTermination(status, _, executable, processIdentifier):
      switch status {
      case .exited(let code):
        return "Process \(processIdentifier) (\(executable)) exited with code \(code), which is not an acceptable exit"
      case .signalled(let signo):
        return "Process \(processIdentifier) (\(executable)) terminated with signal \(signo), which is not an acceptable exit"
      }
    }
  }
}

extension Subprocess {

  /// Launches the process on the host, waits for it to terminate, and
  /// returns its termination status alongside whatever the output captures
  /// produced.
  ///
  /// Throws `SubprocessError.unacceptableTermination` when the termination
  /// does not satisfy `exitPolicy` — note that a signal never satisfies a
  /// code-based policy.
  ///
  /// Cancellation stops observation of the process but does not kill it,
  /// matching the engine underneath; use `sendSignal` on a launched handle
  /// to terminate a process.
  public func run<Out: Sendable, Err: Sendable>(
    output: Output<Out>,
    error: Output<Err>,
    exitPolicy: ExitPolicy = .mustExitZero,
    logger: (any FBControlCoreLogger)? = nil
  ) async throws -> Completed<Out, Err> {
    let stdOut = output.resolve()
    let stdErr = error.resolve()
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: stdOut.output, stdErr: stdErr.output)
    let configuration = FBProcessSpawnConfiguration(
      launchPath: executable,
      arguments: arguments,
      environment: environment.resolved(against: ProcessInfo.processInfo.environment),
      io: io,
      mode: mode.spawnMode)

    let process = try await bridgeFBFuture(
      FBSubprocess<AnyObject, AnyObject, AnyObject>.launchProcess(with: configuration, logger: logger))
    // `statLoc` resolves only after the IO attachment has torn down, so the
    // captures below are complete by the time it is readable. It also never
    // errors on termination, unlike the `exitCode`/`signal` pair.
    let statLoc = try await bridgeFBFuture(process.statLoc)

    let status = TerminationStatus(statLoc: statLoc.int32Value)
    guard exitPolicy.accepts(status) else {
      throw SubprocessError.unacceptableTermination(
        status: status,
        policy: exitPolicy,
        executable: executable,
        processIdentifier: process.processIdentifier)
    }
    return Completed(
      executable: executable,
      processIdentifier: process.processIdentifier,
      terminationStatus: status,
      standardOutput: stdOut.capture(),
      standardError: stdErr.capture())
  }

  /// As `run(output:error:exitPolicy:logger:)`, capturing both streams in
  /// memory as strings — the same default an unconfigured `FBProcessBuilder`
  /// applies, made visible in the return type.
  public func run(
    exitPolicy: ExitPolicy = .mustExitZero,
    logger: (any FBControlCoreLogger)? = nil
  ) async throws -> Completed<String, String> {
    try await run(output: .string, error: .string, exitPolicy: exitPolicy, logger: logger)
  }
}

extension Subprocess.LaunchMode {
  var spawnMode: ProcessSpawnMode {
    switch self {
    case .default:
      return .default
    case .posixSpawn:
      return .posixSpawn
    case .launchd:
      return .launchd
    }
  }
}

extension Subprocess.Output {

  /// Translates the capture into the engine's sink object, paired with a
  /// reader for the captured value once the process has terminated.
  func resolve() -> (output: FBProcessOutput<AnyObject>?, capture: () -> Captured) {
    switch kind {
    case .closed:
      return (nil, { Self.captured(()) })
    case .nullDevice:
      // `FBProcessOutput.outputForNullDevice` attaches descriptor -1, which
      // the host engine cannot duplicate onto the child — an actually-open
      // /dev/null only exists as a file-path output.
      return (FBProcessOutput<AnyObject>(forFilePath: "/dev/null"), { Self.captured(()) })
    case .consumer(let consumer):
      return (FBProcessOutput<AnyObject>(for: consumer), { Self.captured(()) })
    case .logger(let logger):
      return (FBProcessOutput<AnyObject>(for: logger), { Self.captured(()) })
    case .loggerCapturingErrorMessage(let logger):
      let buffer = FBDataBuffer.accumulatingBuffer(withCapacity: FBProcessOutputErrorMessageLength)
      return (FBProcessOutput<AnyObject>(for: buffer, logger: logger), { Self.captured(()) })
    case .lines(let sink):
      let consumer = FBBlockDataConsumer.asynchronousLineConsumer(sink)
      return (FBProcessOutput<AnyObject>(for: consumer), { Self.captured(()) })
    case .data:
      let backing = NSMutableData()
      return (FBProcessOutput<AnyObject>(to: backing), { Self.captured(backing as Data) })
    case .string:
      let contents = FBProcessOutput<AnyObject>(toStringBackedBy: NSMutableData())
      return (contents, { Self.captured(contents.contents) })
    case .file(let url):
      return (FBProcessOutput<AnyObject>(forFilePath: url.path), { Self.captured(url) })
    }
  }

  private static func captured(_ value: Any) -> Captured {
    guard let captured = value as? Captured else {
      preconditionFailure("A \(Captured.self) capture was paired with a sink that produced \(type(of: value)); the factory initializers make this unreachable")
    }
    return captured
  }
}
