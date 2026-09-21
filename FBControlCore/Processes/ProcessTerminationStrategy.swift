/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let ProcessTableRemovalTimeout: TimeInterval = 20.0

/// An Option Set for Process Termination.
public struct ProcessTerminationStrategyOptions: OptionSet, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }

  /// Checks for the process to exist before signalling.
  public static let checkProcessExistsBeforeSignal = ProcessTerminationStrategyOptions(rawValue: 1 << 2)
  /// Waits for the process to die before returning.
  public static let checkDeathAfterSignal = ProcessTerminationStrategyOptions(rawValue: 1 << 3)
  /// Whether to backoff to SIGKILL if a less severe signal fails.
  public static let backoffToSIGKILL = ProcessTerminationStrategyOptions(rawValue: 1 << 4)
}

/// A Configuration for the Strategy.
public struct ProcessTerminationStrategyConfiguration: Sendable {
  public var signo: Int32
  public var options: ProcessTerminationStrategyOptions

  public init(signo: Int32, options: ProcessTerminationStrategyOptions) {
    self.signo = signo
    self.options = options
  }
}

private let FBProcessTerminationStrategyConfigurationDefault = ProcessTerminationStrategyConfiguration(
  signo: SIGKILL,
  options: [.checkProcessExistsBeforeSignal, .checkDeathAfterSignal, .backoffToSIGKILL]
)

enum ProcessTerminationStrategyError: Error, LocalizedError {
  case processDoesNotExist(processIdentifier: pid_t)
  case killFailed(processIdentifier: pid_t, message: String)
  /// Never produced: exceeding the process table removal timeout is reported as
  /// `processDidNotDisappear`, or escalated to SIGKILL. Kept for source compatibility.
  case processTableRemovalTimedOut(processIdentifier: pid_t)
  case processDidNotDisappear(processIdentifier: pid_t, processInfo: String)
  case sigkillAfterFailedKill(processIdentifier: pid_t, signo: Int32, underlying: Error)

  public var errorDescription: String? {
    switch self {
    case let .processDoesNotExist(processIdentifier):
      return "Could not find that process \(processIdentifier) exists"
    case let .killFailed(processIdentifier, message):
      return "Failed to kill \(processIdentifier): '\(message)'"
    case let .processTableRemovalTimedOut(processIdentifier):
      return "Process \(processIdentifier) to be removed from the process table"
    case let .processDidNotDisappear(processIdentifier, _):
      return "Timed out waiting for \(processIdentifier) to disappear from the process table"
    case let .sigkillAfterFailedKill(processIdentifier, signo, _):
      return "Attempted to SIGKILL \(processIdentifier) after failed kill with signo \(signo)"
    }
  }
}

// SAFETY: every stored property is immutable; the fetcher serialises its own buffers, and the
// logger is shared across threads throughout the tree.
// patternlint-disable-next-line unchecked-sendable
public final class ProcessTerminationStrategy: @unchecked Sendable {

  // MARK: - Private Properties

  private let configuration: ProcessTerminationStrategyConfiguration
  private let processFetcher: ProcessFetcher
  private let workQueue: DispatchQueue
  private let logger: ControlCoreLogger

  // MARK: - Initializers

  public class func strategy(
    withConfiguration configuration: ProcessTerminationStrategyConfiguration,
    processFetcher: ProcessFetcher,
    workQueue: DispatchQueue,
    logger: ControlCoreLogger
  ) -> Self {
    self.init(configuration: configuration, processFetcher: processFetcher, workQueue: workQueue, logger: logger)
  }

  public class func strategy(
    withProcessFetcher processFetcher: ProcessFetcher,
    workQueue: DispatchQueue,
    logger: ControlCoreLogger
  ) -> Self {
    self.init(
      configuration: FBProcessTerminationStrategyConfigurationDefault,
      processFetcher: processFetcher,
      workQueue: workQueue,
      logger: logger
    )
  }

  required init(
    configuration: ProcessTerminationStrategyConfiguration,
    processFetcher: ProcessFetcher,
    workQueue: DispatchQueue,
    logger: ControlCoreLogger
  ) {
    precondition(
      configuration.signo > 0 && configuration.signo < 32,
      "Signal must be greater than 0 (SIGHUP) and less than 32 (SIGUSR2) was \(configuration.signo)")
    self.configuration = configuration
    self.processFetcher = processFetcher
    self.workQueue = workQueue
    self.logger = logger
  }

  // MARK: - Public Methods

  public func killProcessIdentifier(_ processIdentifier: pid_t) async throws {
    let checkExists = hasOption(.checkProcessExistsBeforeSignal)
    if checkExists && processFetcher.processInfo(for: processIdentifier) == nil {
      throw ProcessTerminationStrategyError.processDoesNotExist(processIdentifier: processIdentifier)
    }

    logger.debug().log("Killing \(processIdentifier)")
    if kill(processIdentifier, configuration.signo) != 0 {
      throw ProcessTerminationStrategyError.killFailed(processIdentifier: processIdentifier, message: String(cString: strerror(errno)))
    }

    let checkDeath = hasOption(.checkDeathAfterSignal)
    if !checkDeath {
      logger.debug().log("Killed \(processIdentifier)")
      return
    }

    logger.debug().log("Waiting on \(processIdentifier) to disappear from the process table")
    if try await waitForProcessIdentifierToDie(processIdentifier) {
      logger.debug().log("Process \(processIdentifier) terminated")
      return
    }

    let backoff = hasOption(.backoffToSIGKILL)
    if configuration.signo == SIGKILL || !backoff {
      let processInfo: Any = processFetcher.processInfo(for: processIdentifier) ?? ("No Process Info" as NSString)
      throw ProcessTerminationStrategyError.processDidNotDisappear(processIdentifier: processIdentifier, processInfo: String(describing: processInfo))
    }

    var newConfiguration = configuration
    newConfiguration.signo = SIGKILL
    logger.debug().log("Backing off kill of \(processIdentifier) to SIGKILL")
    do {
      try await strategyWith(configuration: newConfiguration).killProcessIdentifier(processIdentifier)
    } catch {
      throw ProcessTerminationStrategyError.sigkillAfterFailedKill(processIdentifier: processIdentifier, signo: configuration.signo, underlying: error)
    }
  }

  // MARK: - Private

  private func hasOption(_ option: ProcessTerminationStrategyOptions) -> Bool {
    configuration.options.contains(option)
  }

  private func strategyWith(configuration: ProcessTerminationStrategyConfiguration) -> ProcessTerminationStrategy {
    ProcessTerminationStrategy(
      configuration: configuration,
      processFetcher: processFetcher,
      workQueue: workQueue,
      logger: logger
    )
  }

  /// Returns false when the process was still in the process table at the deadline.
  private func waitForProcessIdentifierToDie(_ processIdentifier: pid_t) async throws -> Bool {
    let processFetcher = self.processFetcher
    do {
      try await pollUntilTrue(
        on: workQueue,
        deadline: PollDeadline(timeout: ProcessTableRemovalTimeout, waitingFor: "process \(processIdentifier) to be removed from the process table")
      ) {
        processFetcher.processInfo(for: processIdentifier) == nil
      }
      return true
    } catch is PollTimeoutError {
      return false
    }
  }
}
