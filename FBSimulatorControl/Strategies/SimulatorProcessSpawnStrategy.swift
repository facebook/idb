/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

enum SimulatorProcessSpawnError: Error {
  case stdInUnsupported
}

extension SimulatorProcessSpawnError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .stdInUnsupported:
      return "A process cannot be spawned on a Simulator with a stdin attached, as SimDevice provides no way of connecting one"
    }
  }
}

final class SimulatorProcessSpawnStrategy {

  // MARK: - Launch Options

  static func launchOptions(withArguments arguments: [String], environment: [String: String], waitForDebugger: Bool) -> [String: Any] {
    var options: [String: Any] = [:]
    options["arguments"] = arguments
    options["environment"] = environment
    if waitForDebugger {
      options["wait_for_debugger"] = NSNumber(value: 1)
    }
    return options
  }

  static func spawn(_ simulator: Simulator, configuration: ProcessSpawnConfiguration) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    // Rejected before attaching, so that no file descriptor is opened for an input
    // that could never be read: SimDevice's launch options address stdout and stderr
    // by file descriptor and have no equivalent for stdin.
    guard configuration.io.stdIn == nil else {
      throw SimulatorProcessSpawnError.stdInUnsupported
    }
    let attachment = try await bridgeFBFuture(configuration.io.attach())
    return try await launchProcess(
      withSimulator: simulator,
      configuration: configuration,
      attachment: attachment
    )
  }

  private static func launchProcess(withSimulator simulator: Simulator, configuration: ProcessSpawnConfiguration, attachment: FBProcessIOAttachment) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    let logger = simulator.logger
    let statLoc = FBMutableFuture<NSNumber>(name: "Process completion of \(configuration.launchPath) on \(simulator.udid)")
    let exitCode = FBMutableFuture<NSNumber>(name: "Process exit of \(configuration.launchPath) on \(simulator.udid)")
    let signal = FBMutableFuture<NSNumber>(name: "Process signal of \(configuration.launchPath) on \(simulator.udid)")

    let options = simDeviceLaunchOptions(
      withSimulator: simulator,
      launchPath: configuration.launchPath,
      arguments: configuration.arguments,
      environment: configuration.environment,
      waitForDebugger: false,
      stdOut: attachment.stdOut,
      stdErr: attachment.stdErr,
      mode: configuration.mode
    )

    // PID is needed by the termination handler for logging; we populate the
    // holder once `spawnAsync` returns it. The terminationHandler will only be
    // invoked after the process exits, which strictly follows that return.
    let pidHolder = PIDHolder()
    let processIdentifier = try await simulator.device.spawnAsync(
      withPath: configuration.launchPath,
      options: options,
      terminationQueue: simulator.workQueue,
      terminationHandler: { (statLocValue: Int32) in
        // The attachment descriptors are closed exactly once, by the detach that
        // resolveProcessFinished runs. Closing them here as well would race that
        // asynchronous teardown and double-close recycled descriptor numbers,
        // which crashes whichever component now owns them (EV_VANISHED on
        // dispatch-source-monitored descriptors, EBADF traps in SwiftNIO).
        ProcessSpawnCommandHelpers.resolveProcessFinished(
          withStatLoc: statLocValue,
          inTeardownOfIOAttachment: attachment,
          statLocFuture: statLoc,
          exitCodeFuture: exitCode,
          signalFuture: signal,
          processIdentifier: pidHolder.value,
          configuration: configuration,
          queue: simulator.workQueue,
          logger: logger
        )
      },
      completionQueue: simulator.workQueue
    )
    pidHolder.value = processIdentifier

    return FBSubprocess<AnyObject, AnyObject, AnyObject>(
      processIdentifier: processIdentifier,
      statLoc: convertFBMutableFuture(statLoc),
      exitCode: convertFBMutableFuture(exitCode),
      signal: convertFBMutableFuture(signal),
      configuration: configuration,
      queue: simulator.workQueue
    )
  }

  /// Lets the termination handler reach the PID once it's known, since
  /// `spawnAsync` produces the PID after the handler is registered.
  private final class PIDHolder: @unchecked Sendable {
    var value: Int32 = 0
  }

  static func simDeviceLaunchOptions(withSimulator simulator: Simulator, launchPath: String, arguments: [String], environment: [String: String], waitForDebugger: Bool, stdOut: FBProcessStreamAttachment?, stdErr: FBProcessStreamAttachment?, mode: ProcessSpawnMode) -> [String: Any] {
    simDeviceLaunchOptions(
      withSimulator: simulator,
      launchPath: launchPath,
      arguments: arguments,
      environment: environment,
      waitForDebugger: waitForDebugger,
      standardOutput: stdOut?.fileDescriptor,
      standardError: stdErr?.fileDescriptor,
      mode: mode)
  }

  static func simDeviceLaunchOptions(withSimulator simulator: Simulator, launchPath: String, arguments: [String], environment: [String: String], waitForDebugger: Bool, standardOutput: Int32?, standardError: Int32?, mode: ProcessSpawnMode) -> [String: Any] {
    // argv[0] should be launch path of the process. SimDevice does not do this automatically, so we need to add it.
    let fullArguments = [launchPath] + arguments
    var options = launchOptions(withArguments: fullArguments, environment: environment, waitForDebugger: waitForDebugger)
    if let standardOutput {
      options["stdout"] = NSNumber(value: standardOutput)
    }
    if let standardError {
      options["stderr"] = NSNumber(value: standardError)
    }
    options["standalone"] = NSNumber(value: shouldLaunchStandalone(onSimulator: simulator, mode: mode))
    return options
  }

  static func shouldLaunchStandalone(onSimulator simulator: Simulator, mode: ProcessSpawnMode) -> Bool {
    switch mode {
    case .launchd:
      return false
    case .posixSpawn:
      return true
    default:
      return simulator.state != .booted
    }
  }
}

/// Spawns inside a simulator with `SimDevice`.
///
/// `SimDevice` addresses stdout and stderr by descriptor but has no way of
/// connecting a stdin, so only a `.closed` input is accepted.
public struct SimulatorSubprocessLauncher: SubprocessLauncher {

  let simulator: Simulator

  public init(simulator: Simulator) {
    self.simulator = simulator
  }

  public var supportsStandardInput: Bool {
    false
  }

  public func spawn(
    _ subprocess: Subprocess,
    standardInput: Int32?,
    standardOutput: Int32?,
    standardError: Int32?,
    logger: (any ControlCoreLogger)?
  ) async throws -> LaunchedProcess {
    let options = SimulatorProcessSpawnStrategy.simDeviceLaunchOptions(
      withSimulator: simulator,
      launchPath: subprocess.executable,
      arguments: subprocess.arguments,
      // Nothing of this process's environment belongs inside the simulator, so
      // the inheriting cases resolve to nothing and only explicit variables pass.
      environment: subprocess.environment.resolved(against: [:]),
      waitForDebugger: false,
      standardOutput: standardOutput,
      standardError: standardError,
      mode: ProcessSpawnMode(subprocess.mode))
    let exit = SimulatorExit()
    let processIdentifier = try await simulator.device.spawnAsync(
      withPath: subprocess.executable,
      options: options,
      terminationQueue: simulator.asyncQueue,
      terminationHandler: { statLoc in exit.resolve(statLoc) },
      completionQueue: simulator.asyncQueue
    )
    return LaunchedProcess(processIdentifier: processIdentifier) {
      await exit.statLoc()
    }
  }
}

/// Holds the status from `SimDevice`'s termination handler until the exit
/// monitor asks for it, whichever comes first.
///
// SAFETY: `resolved` and `waiter` are only read or written inside `lock`, and
// the continuation is resumed after the lock is released.
// patternlint-disable-next-line unchecked-sendable
private final class SimulatorExit: @unchecked Sendable {
  private let lock = NSLock()
  private var resolved: Int32?
  private var waiter: CheckedContinuation<Int32, Never>?

  func resolve(_ statLoc: Int32) {
    let waiting: CheckedContinuation<Int32, Never>? = lock.withLock {
      resolved = statLoc
      defer { waiter = nil }
      return waiter
    }
    waiting?.resume(returning: statLoc)
  }

  func statLoc() async -> Int32 {
    await withCheckedContinuation { continuation in
      let immediate: Int32? = lock.withLock {
        if let resolved {
          return resolved
        }
        waiter = continuation
        return nil
      }
      if let immediate {
        continuation.resume(returning: immediate)
      }
    }
  }
}

extension ProcessSpawnMode {
  init(_ mode: Subprocess.LaunchMode) {
    switch mode {
    case .default:
      self = .default
    case .posixSpawn:
      self = .posixSpawn
    case .launchd:
      self = .launchd
    }
  }
}
