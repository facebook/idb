/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let CrashLogStartDateFuzz: TimeInterval = -20
private let CrashLogWaitTime: TimeInterval = 180
private let KillBackoffTimeout: TimeInterval = 1

@objc public final class FBXCTestProcess: NSObject {

  @objc public static func ensureProcess(_ process: FBSubprocess<AnyObject, AnyObject, AnyObject>, completesWithin timeout: TimeInterval, crashLogCommands: FBCrashLogCommands?, queue: DispatchQueue, logger: FBControlCoreLogger) -> FBFuture<NSNumber> {
    let startDate = Date(timeIntervalSinceNow: CrashLogStartDateFuzz)

    logger.log("Waiting for \(process.processIdentifier) to exit within \(timeout) seconds")
    return unsafeBitCast(
      unsafeBitCast(process.statLoc, to: FBFuture<AnyObject>.self)
        .onQueue(
          queue, timeout: timeout,
          handler: {
            return FBXCTestProcess.performSampleStackshot(onProcess: process, forTimeout: timeout, queue: queue, logger: logger)
          }
        )
        .onQueue(
          queue,
          fmap: { _ -> FBFuture<AnyObject> in
            return unsafeBitCast(process.exitCode, to: FBFuture<AnyObject>.self)
              .onQueue(
                queue,
                chain: { exitCodeFuture -> FBFuture<AnyObject> in
                  if exitCodeFuture.state == .done {
                    return exitCodeFuture
                  }
                  guard let crashLogCommands else {
                    return exitCodeFuture
                  }
                  return unsafeBitCast(
                    FBXCTestProcess.performCrashLogQuery(forProcess: process, startDate: startDate, crashLogCommands: crashLogCommands, crashLogWaitTime: CrashLogWaitTime, queue: queue, logger: logger),
                    to: FBFuture<AnyObject>.self
                  )
                })
          }),
      to: FBFuture<NSNumber>.self
    )
  }

  @objc public static func describeFailingExitCode(_ exitCode: Int32) -> String? {
    switch exitCode {
    case 0, 1:
      return nil
    case 10: // TestShimExitCodeDLOpenError
      return "DLOpen Error"
    case 11: // TestShimExitCodeBundleOpenError
      return "Error opening test bundle"
    case 12: // TestShimExitCodeMissingExecutable
      return "Missing executable"
    case 13: // TestShimExitCodeXCTestFailedLoading
      return "XCTest Framework failed loading"
    default:
      return "Unknown xctest exit code \(exitCode)"
    }
  }

  // MARK: Private

  private static func performSampleStackshot(onProcess process: FBSubprocess<AnyObject, AnyObject, AnyObject>, forTimeout timeout: TimeInterval, queue: DispatchQueue, logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    return (FBProcessFetcher.performSampleStackshot(forProcessIdentifier: process.processIdentifier, queue: queue) as FBFuture)
      .onQueue(
        queue,
        fmap: { stackshot -> FBFuture<AnyObject> in
          return FBXCTestError.describe("Waited \(timeout) seconds for process \(process.processIdentifier) to terminate, but the xctest process stalled: \(stackshot)").failFuture()
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { _ in
          logger.log("Terminating stalled xctest process \(process)")
          process.sendSignal(SIGTERM, backingOffToKillWithTimeout: KillBackoffTimeout, logger: logger)
            .onQueue(
              queue,
              notifyOfCompletion: { _ in
                logger.log("Stalled xctest process \(process) has been terminated")
              })
        })
  }

  private static func performCrashLogQuery(forProcess process: FBSubprocess<AnyObject, AnyObject, AnyObject>, startDate: Date, crashLogCommands: FBCrashLogCommands, crashLogWaitTime: TimeInterval, queue: DispatchQueue, logger: FBControlCoreLogger) -> FBFuture<NSNumber> {
    logger.log("xctest process (\(process.processIdentifier)) died prematurely, checking for crash log for \(crashLogWaitTime) seconds")
    return unsafeBitCast(
      unsafeBitCast(
        FBXCTestProcess.crashLogs(forTerminationOfProcess: process, since: startDate, crashLogCommands: crashLogCommands, crashLogWaitTime: crashLogWaitTime, queue: queue),
        to: FBFuture<AnyObject>.self
      )
      .rephraseFailure("xctest process (\(process.processIdentifier)) exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports")
      .onQueue(
        queue,
        fmap: { crashInfo -> FBFuture<AnyObject> in
          let info = crashInfo as! FBCrashLogInfo
          let rawLog = (try? info.loadRawCrashLogString()) ?? ""
          return FBXCTestError.describe("xctest process crashed\n\(info)\n\nRaw Crash File Contents\n\(rawLog)").failFuture()
        }),
      to: FBFuture<NSNumber>.self
    )
  }

  private static func crashLogs(forTerminationOfProcess process: FBSubprocess<AnyObject, AnyObject, AnyObject>, since sinceDate: Date, crashLogCommands: FBCrashLogCommands, crashLogWaitTime: TimeInterval, queue: DispatchQueue) -> FBFuture<FBCrashLogInfo> {
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      FBCrashLogInfo.predicateForCrashLogs(withProcessID: process.processIdentifier),
      FBCrashLogInfo.predicateNewerThanDate(sinceDate),
    ])

    return unsafeBitCast(
      unsafeBitCast(crashLogCommands.notify(ofCrash: predicate), to: FBFuture<AnyObject>.self)
        .onQueue(
          queue, timeout: crashLogWaitTime,
          handler: {
            return FBControlCoreError.describe("Crash logs for terminated process \(process.processIdentifier) to appear").failFuture()
          }),
      to: FBFuture<FBCrashLogInfo>.self
    )
  }
}
