/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let ProcessTableRemovalTimeout: TimeInterval = 20.0

private let FBProcessTerminationStrategyConfigurationDefault = FBProcessTerminationStrategyConfiguration(
  signo: SIGKILL,
  options: FBProcessTerminationStrategyOptions(rawValue:
    FBProcessTerminationStrategyOptions.checkProcessExistsBeforeSignal.rawValue
    | FBProcessTerminationStrategyOptions.checkDeathAfterSignal.rawValue
    | FBProcessTerminationStrategyOptions.backoffToSIGKILL.rawValue
  )!
)

@objc(FBProcessTerminationStrategy)
public class FBProcessTerminationStrategy: NSObject {

  // MARK: Private Properties

  private let configuration: FBProcessTerminationStrategyConfiguration
  private let processFetcher: FBProcessFetcher
  private let workQueue: DispatchQueue
  private let logger: FBControlCoreLogger

  // MARK: Initializers

  @objc
  public class func strategy(
    withConfiguration configuration: FBProcessTerminationStrategyConfiguration,
    processFetcher: FBProcessFetcher,
    workQueue: DispatchQueue,
    logger: FBControlCoreLogger
  ) -> Self {
    return self.init(configuration: configuration, processFetcher: processFetcher, workQueue: workQueue, logger: logger)
  }

  @objc
  public class func strategy(
    withProcessFetcher processFetcher: FBProcessFetcher,
    workQueue: DispatchQueue,
    logger: FBControlCoreLogger
  ) -> Self {
    return self.init(
      configuration: FBProcessTerminationStrategyConfigurationDefault,
      processFetcher: processFetcher,
      workQueue: workQueue,
      logger: logger
    )
  }

  required init(
    configuration: FBProcessTerminationStrategyConfiguration,
    processFetcher: FBProcessFetcher,
    workQueue: DispatchQueue,
    logger: FBControlCoreLogger
  ) {
    precondition(configuration.signo > 0 && configuration.signo < 32,
                 "Signal must be greater than 0 (SIGHUP) and less than 32 (SIGUSR2) was \(configuration.signo)")
    self.configuration = configuration
    self.processFetcher = processFetcher
    self.workQueue = workQueue
    self.logger = logger
    super.init()
  }

  // MARK: Public Methods

  @objc
  @discardableResult
  public func killProcessIdentifier(_ processIdentifier: pid_t) -> FBFuture<NSNull> {
    let checkExists = hasOption(.checkProcessExistsBeforeSignal)
    if checkExists && processFetcher.processInfo(for: processIdentifier) == nil {
      return FBControlCoreError
        .describe("Could not find that process \(processIdentifier) exists")
        .failFuture() as! FBFuture<NSNull>
    }

    // Kill the process with kill(2).
    logger.debug().log("Killing \(processIdentifier)")
    if kill(processIdentifier, configuration.signo) != 0 {
      return FBControlCoreError
        .describe("Failed to kill \(processIdentifier): '\(String(cString: strerror(errno)))'")
        .failFuture() as! FBFuture<NSNull>
    }

    let checkDeath = hasOption(.checkDeathAfterSignal)
    if !checkDeath {
      logger.debug().log("Killed \(processIdentifier)")
      return FBFuture<NSNull>.empty()
    }

    // It may take some time for the process to have truly died, so wait for it to be so.
    logger.debug().log("Waiting on \(processIdentifier) to dissappear from the process table")

    let waitFuture: FBFuture<NSNull> = waitForProcessIdentifierToDie(processIdentifier, on: workQueue, processFetcher: processFetcher)

    return waitFuture
      .onQueue(workQueue, timeout: ProcessTableRemovalTimeout, handler: { () -> FBFuture<AnyObject> in
        return FBControlCoreError
          .describe("Process \(processIdentifier) to be removed from the process table")
          .failFuture()
      })
      .onQueue(workQueue, chain: { (future: FBFuture<AnyObject>) -> FBFuture<AnyObject> in
        if future.result != nil {
          self.logger.debug().log("Process \(processIdentifier) terminated")
          return FBFuture<NSNull>.empty() as! FBFuture<AnyObject>
        }
        let backoff = self.hasOption(.backoffToSIGKILL)
        if self.configuration.signo == SIGKILL || !backoff {
          let processInfo: Any = self.processFetcher.processInfo(for: processIdentifier) ?? ("No Process Info" as NSString)
          return FBControlCoreError
            .describe("Timed out waiting for \(processIdentifier) to dissapear from the process table")
            .extraInfo("\(processIdentifier)_process", value: processInfo)
            .failFuture()
        }

        // Try with SIGKILL instead.
        var newConfiguration = self.configuration
        newConfiguration.signo = SIGKILL
        self.logger.debug().log("Backing off kill of \(processIdentifier) to SIGKILL")
        let sigkillFuture: FBFuture<NSNull> = self.strategyWith(configuration: newConfiguration)
          .killProcessIdentifier(processIdentifier)

        // Inline rephraseFailure since the ObjC method is variadic and cannot be called from Swift
        return sigkillFuture.onQueue(self.workQueue, chain: { (innerFuture: FBFuture<AnyObject>) -> FBFuture<AnyObject> in
          if let error = innerFuture.error {
            return FBControlCoreError
              .describe("Attempted to SIGKILL \(processIdentifier) after failed kill with signo \(self.configuration.signo)")
              .caused(by: error)
              .failFuture()
          }
          return innerFuture
        })
      }) as! FBFuture<NSNull>
  }

  // MARK: Private

  private func hasOption(_ option: FBProcessTerminationStrategyOptions) -> Bool {
    return (configuration.options.rawValue & option.rawValue) == option.rawValue
  }

  private func strategyWith(configuration: FBProcessTerminationStrategyConfiguration) -> FBProcessTerminationStrategy {
    return FBProcessTerminationStrategy(
      configuration: configuration,
      processFetcher: processFetcher,
      workQueue: workQueue,
      logger: logger
    )
  }

  private func waitForProcessIdentifierToDie(_ processIdentifier: pid_t, on queue: DispatchQueue, processFetcher: FBProcessFetcher) -> FBFuture<NSNull> {
    return FBFuture<NSNull>.onQueue(queue, resolveWhen: {
      return processFetcher.processInfo(for: processIdentifier) == nil
    })
  }
}
