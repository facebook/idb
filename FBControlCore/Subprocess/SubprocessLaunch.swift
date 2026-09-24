/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A process that has been launched and not yet observed to terminate.
///
/// The handle does not own the process's lifetime: dropping it neither kills
/// nor unreaps the child, whose exit is always collected. `withRunning` is
/// the lexical alternative that does own the lifetime.
public struct RunningSubprocess: Sendable {

  public let processIdentifier: pid_t
  let exit: ExitBroadcast
  let logger: (any ControlCoreLogger)?

  /// The termination status, awaitable from any number of tasks.
  /// Throws only `CancellationError`; cancellation abandons observation
  /// without affecting the process.
  public var terminationStatus: TerminationStatus {
    get async throws {
      try await exit.status()
    }
  }

  /// Sends `signo` to the process, unless it has already terminated.
  public func sendSignal(_ signo: Int32) {
    // Reaped is checked rather than resolved: the status resolves only after the
    // drains finish, and a reaped pid can be recycled in that window.
    guard !exit.hasBeenReaped else {
      return
    }
    kill(processIdentifier, signo)
  }

  /// Sends `SIGTERM`, escalating to `SIGKILL` if the process has not
  /// terminated within `gracePeriod`, and returns the termination status.
  @discardableResult
  public func terminate(gracePeriod: TimeInterval) async throws -> TerminationStatus {
    sendSignal(SIGTERM)
    if let status = try await exit.status(within: gracePeriod) {
      return status
    }
    logger?.log("Process \(processIdentifier) didn't exit after wait for \(gracePeriod) seconds for sending signal \(SIGTERM), sending SIGKILL now.")
    sendSignal(SIGKILL)
    return try await exit.status()
  }

  /// As `terminate(gracePeriod:)`, but completes even when the surrounding
  /// task is already cancelled — teardown must not strand a child.
  func terminateIgnoringCancellation(gracePeriod: TimeInterval) async {
    let running = self
    await Task {
      sendSignal(SIGTERM)
      if await running.exit.statusIgnoringCancellation(within: gracePeriod) != nil {
        return
      }
      running.logger?.log("Process \(running.processIdentifier) didn't exit after wait for \(gracePeriod) seconds for sending signal \(SIGTERM), sending SIGKILL now.")
      running.sendSignal(SIGKILL)
      _ = await running.exit.statusIgnoringCancellation(within: nil)
    }.value
  }
}

extension Subprocess {

  /// Launches on the host and returns an escaping handle, for lifetimes
  /// that genuinely are not lexical. Both streams must be live sinks —
  /// captures that materialize at exit have nowhere to go.
  public func launch(
    output: Output<Void>,
    error: Output<Void>,
    logger: (any ControlCoreLogger)? = nil
  ) async throws -> RunningSubprocess {
    var (stdOut, _) = try output.resolveHost()
    var (stdErr, _): (HostSink, () -> Void)
    do {
      (stdErr, _) = try error.resolveHost()
    } catch let failure {
      stdOut.dispose()
      throw failure
    }
    return try await startOnHost(stdOut: &stdOut, stdErr: &stdErr, logger: logger)
  }

  /// Launches on the host, runs `body` against the live process, and
  /// terminates it when the scope exits — on return, on a thrown error, and
  /// on cancellation alike.
  public func withRunning<Result: Sendable>(
    output: Output<Void>,
    error: Output<Void>,
    gracePeriod: TimeInterval = 4,
    logger: (any ControlCoreLogger)? = nil,
    _ body: (RunningSubprocess) async throws -> Result
  ) async throws -> Result {
    let running = try await launch(output: output, error: error, logger: logger)
    do {
      let result = try await body(running)
      await running.terminateIgnoringCancellation(gracePeriod: gracePeriod)
      return result
    } catch let failure {
      await running.terminateIgnoringCancellation(gracePeriod: gracePeriod)
      throw failure
    }
  }

  /// Spawns with the resolved sinks and installs the exit monitor: exit
  /// event → drains complete → status resolved. Every observer of the
  /// returned broadcast therefore sees termination only after output has
  /// finished draining.
  func startOnHost(
    stdOut: inout HostSink,
    stdErr: inout HostSink,
    logger: (any ControlCoreLogger)?
  ) async throws -> RunningSubprocess {
    let processName = (executable as NSString).lastPathComponent
    let processIdentifier: pid_t
    do {
      for reader in [stdOut.reader, stdErr.reader].compactMap({ $0 }) {
        _ = try await bridgeFBFuture(reader.startReading())
      }
      processIdentifier = try HostSubprocess.spawn(
        executable: executable,
        arguments: arguments,
        environment: environment.resolved(against: ProcessInfo.processInfo.environment),
        standardOutput: stdOut.childDescriptor,
        standardError: stdErr.childDescriptor)
    } catch let failure {
      stdOut.dispose()
      stdErr.dispose()
      throw failure
    }
    stdOut.closeChildDescriptor()
    stdErr.closeChildDescriptor()
    logger?.log("\(processName) Launched with pid \(processIdentifier)")

    let exit = ExitBroadcast()
    let readers = [stdOut.reader, stdErr.reader].compactMap { $0 }
    Task {
      let statLoc = await HostSubprocess.exitStatLoc(of: processIdentifier, logger: logger)
      exit.markReaped()
      for reader in readers {
        _ = try? await bridgeFBFuture(reader.finishedReading(withTimeout: HostSubprocess.drainTimeout))
      }
      let status = TerminationStatus(statLoc: statLoc)
      switch status {
      case .exited(let code):
        logger?.log("Process \(processIdentifier) (\(processName)) exited with code \(code)")
      case .signalled(let signo):
        logger?.log("Process \(processIdentifier) (\(processName)) exited with signal \(signo)")
      }
      exit.resolve(status)
    }
    return RunningSubprocess(processIdentifier: processIdentifier, exit: exit, logger: logger)
  }
}

/// A one-shot, multi-awaiter termination status.
///
// SAFETY: `reaped`, `resolved`, `waiters` and `cancelledWaiters` are only ever read or
// written inside `lock`, and every continuation is resumed after the lock is
// released, so no caller code runs under it.
// patternlint-disable-next-line unchecked-sendable
final class ExitBroadcast: @unchecked Sendable {
  private let lock = NSLock()
  private var reaped = false
  private var resolved: TerminationStatus?
  private var waiters: [UUID: CheckedContinuation<TerminationStatus, any Error>] = [:]
  private var cancelledWaiters: Set<UUID> = []

  var current: TerminationStatus? {
    lock.withLock { resolved }
  }

  /// Whether the process has been reaped, which precedes resolution by the drains.
  var hasBeenReaped: Bool {
    lock.withLock { reaped || resolved != nil }
  }

  func markReaped() {
    lock.withLock { reaped = true }
  }

  func resolve(_ status: TerminationStatus) {
    let continuations: [CheckedContinuation<TerminationStatus, any Error>] = lock.withLock {
      guard resolved == nil else {
        return []
      }
      resolved = status
      let pending = Array(waiters.values)
      waiters.removeAll()
      return pending
    }
    for continuation in continuations {
      continuation.resume(returning: status)
    }
  }

  /// Awaits resolution; throws only `CancellationError`.
  func status() async throws -> TerminationStatus {
    let identifier = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let immediate: Result<TerminationStatus, any Error>? = lock.withLock {
          if cancelledWaiters.remove(identifier) != nil {
            return .failure(CancellationError())
          }
          if let resolved {
            return .success(resolved)
          }
          waiters[identifier] = continuation
          return nil
        }
        if let immediate {
          continuation.resume(with: immediate)
        }
      }
    } onCancel: {
      let continuation: CheckedContinuation<TerminationStatus, any Error>? = lock.withLock {
        guard let waiting = waiters.removeValue(forKey: identifier) else {
          cancelledWaiters.insert(identifier)
          return nil
        }
        return waiting
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  /// Awaits resolution for up to `deadline` (forever when nil); nil on
  /// timeout. Throws only `CancellationError`.
  func status(within deadline: TimeInterval?) async throws -> TerminationStatus? {
    guard let deadline else {
      return try await status()
    }
    return try await withThrowingTaskGroup(of: TerminationStatus?.self) { group in
      group.addTask { try await self.status() }
      group.addTask {
        try await Task.sleep(for: .seconds(deadline))
        return nil
      }
      guard let first = try await group.next() else {
        preconditionFailure("The task group has two children; next() cannot be empty")
      }
      group.cancelAll()
      return first
    }
  }

  /// As `status(within:)`, from a poll rather than a waiter, so it completes
  /// even inside an already-cancelled task.
  func statusIgnoringCancellation(within deadline: TimeInterval?) async -> TerminationStatus? {
    let pollInterval: TimeInterval = 0.02
    var waited: TimeInterval = 0
    while true {
      if let resolved = current {
        return resolved
      }
      if let deadline, waited >= deadline {
        return nil
      }
      // A detached task does not inherit the caller's cancellation, so the
      // sleep really sleeps; `Task.sleep` in a cancelled task returns at once.
      await Task.detached { try? await Task.sleep(for: .seconds(pollInterval)) }.value
      waited += pollInterval
    }
  }
}
