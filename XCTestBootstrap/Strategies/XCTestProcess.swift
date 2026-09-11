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

enum XCTestProcessError: Error {
  case stalled(timeout: TimeInterval, processIdentifier: pid_t, stackshot: String)
  case crashed(info: String, rawLog: String)
  case crashLogTimedOut(processIdentifier: pid_t)
}

extension XCTestProcessError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .stalled(timeout, processIdentifier, stackshot):
      return "Waited \(timeout) seconds for process \(processIdentifier) to terminate, but the xctest process stalled: \(stackshot)"
    case let .crashed(info, rawLog):
      return "xctest process crashed\n\(info)\n\nRaw Crash File Contents\n\(rawLog)"
    case let .crashLogTimedOut(processIdentifier):
      return "Crash logs for terminated process \(processIdentifier) to appear"
    }
  }
}

final class XCTestProcess {

  public static func ensureProcess(_ process: FBSubprocess<AnyObject, AnyObject, AnyObject>, completesWithin timeout: TimeInterval, crashLogCommands: (any CrashLogCommands)?, queue: DispatchQueue, logger: FBControlCoreLogger) -> FBFuture<NSNumber> {
    let startDate = Date(timeIntervalSinceNow: CrashLogStartDateFuzz)

    logger.log("Waiting for \(process.processIdentifier) to exit within \(timeout) seconds")
    return
      process.statLoc.retyped(FBFuture<AnyObject>.self)
      .onQueue(
        queue, timeout: timeout,
        handler: {
          XCTestProcess.performSampleStackshot(onProcess: process, forTimeout: timeout, queue: queue, logger: logger)
        }
      )
      .onQueue(
        queue,
        fmap: { _ -> FBFuture<AnyObject> in
          process.exitCode.retyped(FBFuture<AnyObject>.self)
            .onQueue(
              queue,
              chain: { exitCodeFuture -> FBFuture<AnyObject> in
                if exitCodeFuture.state == .done {
                  return exitCodeFuture
                }
                guard let crashLogCommands else {
                  return exitCodeFuture
                }
                return XCTestProcess.performCrashLogQuery(
                  forProcess: process, startDate: startDate, crashLogCommands: crashLogCommands, crashLogWaitTime: CrashLogWaitTime, queue: queue, logger: logger
                ).retyped(FBFuture<AnyObject>.self)
              })
        }
      )
      .retyped(FBFuture<NSNumber>.self)
  }

  public static func describeFailingExitCode(_ exitCode: Int32) -> String? {
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

  private static func performSampleStackshot(onProcess process: FBSubprocess<AnyObject, AnyObject, AnyObject>, forTimeout timeout: TimeInterval, queue: DispatchQueue, logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    (FBProcessFetcher.performSampleStackshot(forProcessIdentifier: process.processIdentifier, queue: queue) as FBFuture)
      .onQueue(
        queue,
        fmap: { stackshot -> FBFuture<AnyObject> in
          FBFuture(error: XCTestProcessError.stalled(timeout: timeout, processIdentifier: process.processIdentifier, stackshot: String(describing: stackshot)))
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

  private static func performCrashLogQuery(forProcess process: FBSubprocess<AnyObject, AnyObject, AnyObject>, startDate: Date, crashLogCommands: any CrashLogCommands, crashLogWaitTime: TimeInterval, queue: DispatchQueue, logger: FBControlCoreLogger) -> FBFuture<NSNumber> {
    logger.log("xctest process (\(process.processIdentifier)) died prematurely, checking for crash log for \(crashLogWaitTime) seconds")
    return
      XCTestProcess.crashLogs(forTerminationOfProcess: process, since: startDate, crashLogCommands: crashLogCommands, crashLogWaitTime: crashLogWaitTime, queue: queue)
      .rephraseFailure("xctest process (\(process.processIdentifier)) exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports")
      .onQueue(
        queue,
        fmap: { info -> FBFuture<AnyObject> in
          let rawLog = (try? info.loadRawCrashLogString()) ?? ""
          return FBFuture(error: XCTestProcessError.crashed(info: String(describing: info), rawLog: rawLog))
        }
      )
      .retyped(FBFuture<NSNumber>.self)
  }

  private static func crashLogs(forTerminationOfProcess process: FBSubprocess<AnyObject, AnyObject, AnyObject>, since sinceDate: Date, crashLogCommands: any CrashLogCommands, crashLogWaitTime: TimeInterval, queue: DispatchQueue) -> FBFuture<FBCrashLogInfo> {
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      FBCrashLogInfo.predicateForCrashLogs(withProcessID: process.processIdentifier),
      FBCrashLogInfo.predicateNewer(thanDate: sinceDate),
    ])

    let notify: FBFuture<FBCrashLogInfo> = fbFutureFromAsync {
      try await crashLogCommands.notifyOfCrash(matching: predicate)
    }
    return
      notify.retyped(FBFuture<AnyObject>.self)
      .onQueue(
        queue, timeout: crashLogWaitTime,
        handler: {
          FBFuture<AnyObject>(error: XCTestProcessError.crashLogTimedOut(processIdentifier: process.processIdentifier))
        }
      )
      .retyped(FBFuture<FBCrashLogInfo>.self)
  }
}
