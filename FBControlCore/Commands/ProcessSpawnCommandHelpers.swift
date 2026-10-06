/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc
public final class ProcessSpawnCommandHelpers: NSObject {

  @objc
  public class func resolveProcessFinished(
    withStatLoc statLoc: Int32,
    inTeardownOfIOAttachment attachment: FBProcessIOAttachment,
    statLocFuture: FBMutableFuture<NSNumber>,
    exitCodeFuture: FBMutableFuture<NSNumber>,
    signalFuture: FBMutableFuture<NSNumber>,
    processIdentifier: pid_t,
    processName: String,
    queue: DispatchQueue,
    logger: (any ControlCoreLogger)?
  ) {
    // One line per exit: the outcome below logs inside this completion handler,
    // so it inherently reports after IO teardown has finished. The separate
    // tearing-down/completed lines tripled every process exit for no
    // additional information.
    attachment.detach().retyped(FBFuture<AnyObject>.self)
      .onQueue(
        queue,
        notifyOfCompletion: { _ in
          statLocFuture.resolve(withResult: NSNumber(value: statLoc))
          let wstatus = statLoc & 0x7f // _WSTATUS
          if wstatus != 0x7f /* _WSTOPPED */ && wstatus != 0 {
            // WIFSIGNALED
            let signalCode = statLoc & 0x7f // WTERMSIG
            let error = ProcessTerminationError.exitedWithSignal(processIdentifier: processIdentifier, processName: processName, signal: signalCode)
            logger?.log(error.localizedDescription)
            exitCodeFuture.resolveWithError(error)
            signalFuture.resolve(withResult: NSNumber(value: signalCode))
          } else {
            let exitCode = (statLoc >> 8) & 0xff // WEXITSTATUS
            let error = ProcessTerminationError.exitedWithCode(processIdentifier: processIdentifier, processName: processName, exitCode: exitCode)
            logger?.log(error.localizedDescription)
            signalFuture.resolveWithError(error)
            exitCodeFuture.resolve(withResult: NSNumber(value: exitCode))
          }
        })
  }
}
