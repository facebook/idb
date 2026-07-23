/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

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
            let message = "Process \(processIdentifier) (\(configuration.processName)) exited with signal \(signalCode)"
            logger?.log(message)
            let error = FBControlCoreError.describe(message).build()
            exitCodeFuture.resolveWithError(error)
            signalFuture.resolve(withResult: NSNumber(value: signalCode))
          } else {
            let exitCode = (statLoc >> 8) & 0xff // WEXITSTATUS
            let message = "Process \(processIdentifier) (\(configuration.processName)) exited with code \(exitCode)"
            logger?.log(message)
            let error = FBControlCoreError.describe(message).build()
            signalFuture.resolveWithError(error)
            exitCodeFuture.resolve(withResult: NSNumber(value: exitCode))
          }
        })
  }
}
