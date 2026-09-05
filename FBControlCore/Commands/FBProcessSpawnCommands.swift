/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Set as the error on whichever of `exitCode` / `signal` did not happen.
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
    // One line per exit: the outcome below logs inside this completion handler,
    // so it inherently reports after IO teardown has finished. The separate
    // tearing-down/completed lines tripled every process exit for no
    // additional information.
    unsafeBitCast(attachment.detach(), to: FBFuture<AnyObject>.self)
      .onQueue(
        queue,
        notifyOfCompletion: { _ in
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
