/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Process-exit outcomes surfaced as errors on the future that did not happen, as data rather than assembled strings.
public enum FBProcessTerminationError: Error {
  case exitedWithSignal(processIdentifier: pid_t, processName: String, signal: Int32)
  case exitedWithCode(processIdentifier: pid_t, processName: String, exitCode: Int32)
}

extension FBProcessTerminationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .exitedWithSignal(processIdentifier, processName, signal):
      return "Process \(processIdentifier) (\(processName)) exited with signal \(signal)"
    case let .exitedWithCode(processIdentifier, processName, exitCode):
      return "Process \(processIdentifier) (\(processName)) exited with code \(exitCode)"
    }
  }
}

@objc(FBProcessSpawnCommandHelpers)
public final class FBProcessSpawnCommandHelpers: NSObject {

  @objc
  public class func resolveProcessFinished(
    withStatLoc statLoc: Int32,
    inTeardownOfIOAttachment attachment: FBProcessIOAttachment,
    statLocFuture: FBMutableFuture<NSNumber>,
    exitCodeFuture: FBMutableFuture<NSNumber>,
    signalFuture: FBMutableFuture<NSNumber>,
    processIdentifier: pid_t,
    configuration: FBProcessSpawnConfiguration,
    queue: DispatchQueue,
    logger: (any FBControlCoreLogger)?
  ) {
    logger?.log("Process \(processIdentifier) (\(configuration.processName)) has exited, tearing down IO...")
    unsafeBitCast(attachment.detach(), to: FBFuture<AnyObject>.self)
      .onQueue(
        queue,
        notifyOfCompletion: { _ in
          logger?.log("Teardown of IO for process \(processIdentifier) (\(configuration.processName)) has completed")
          statLocFuture.resolve(withResult: NSNumber(value: statLoc))
          let wstatus = statLoc & 0x7f // _WSTATUS
          if wstatus != 0x7f /* _WSTOPPED */ && wstatus != 0 {
            // WIFSIGNALED
            let signalCode = statLoc & 0x7f // WTERMSIG
            let error = FBProcessTerminationError.exitedWithSignal(processIdentifier: processIdentifier, processName: configuration.processName, signal: signalCode)
            logger?.log(error.localizedDescription)
            exitCodeFuture.resolveWithError(error)
            signalFuture.resolve(withResult: NSNumber(value: signalCode))
          } else {
            let exitCode = (statLoc >> 8) & 0xff // WEXITSTATUS
            let error = FBProcessTerminationError.exitedWithCode(processIdentifier: processIdentifier, processName: configuration.processName, exitCode: exitCode)
            logger?.log(error.localizedDescription)
            signalFuture.resolveWithError(error)
            exitCodeFuture.resolve(withResult: NSNumber(value: exitCode))
          }
        })
  }
}
