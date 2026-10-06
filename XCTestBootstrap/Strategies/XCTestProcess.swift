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

  /// Waits for `process` to exit within `timeout` and returns its exit code. A process that
  /// overstays is sampled, terminated and reported as stalled; one killed by a signal is reported
  /// with its crash log when `crashLogCommands` can find one.
  static func awaitExitCode(
    of process: RunningSubprocess,
    processName: String,
    completesWithin timeout: TimeInterval,
    crashLogCommands: (any CrashLogCommands)?,
    logger: ControlCoreLogger,
    sampleStackshot: (pid_t) async throws -> String = ProcessFetcher.sampleStackshot
  ) async throws -> Int32 {
    let startDate = Date(timeIntervalSinceNow: CrashLogStartDateFuzz)
    let processIdentifier = process.processIdentifier

    logger.log("Waiting for \(processIdentifier) to exit within \(timeout) seconds")
    guard let status = try await process.terminationStatus(within: timeout) else {
      let stackshot: Result<String, any Error>
      do {
        stackshot = .success(try await sampleStackshot(processIdentifier))
      } catch {
        stackshot = .failure(error)
      }
      logger.log("Terminating stalled xctest process \(processIdentifier)")
      try await process.terminate(gracePeriod: KillBackoffTimeout)
      logger.log("Stalled xctest process \(processIdentifier) has been terminated")
      throw XCTestProcessError.stalled(timeout: timeout, processIdentifier: processIdentifier, stackshot: try stackshot.get())
    }
    switch status {
    case .exited(let exitCode):
      return exitCode
    case .signalled(let signo):
      guard let crashLogCommands else {
        throw ProcessTerminationError.exitedWithSignal(processIdentifier: processIdentifier, processName: processName, signal: signo)
      }
      return try await bridgeFBFuture(
        XCTestProcess.performCrashLogQuery(forProcessIdentifier: processIdentifier, startDate: startDate, crashLogCommands: crashLogCommands, crashLogWaitTime: CrashLogWaitTime, queue: DispatchQueue.global(qos: .userInitiated), logger: logger)
      ).int32Value
    }
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
    case 14: // TestShimExitCodeTestListWriteError
      return "Failed to write the test list"
    default:
      return "Unknown xctest exit code \(exitCode)"
    }
  }

  private static func performCrashLogQuery(forProcessIdentifier processIdentifier: pid_t, startDate: Date, crashLogCommands: any CrashLogCommands, crashLogWaitTime: TimeInterval, queue: DispatchQueue, logger: ControlCoreLogger) -> FBFuture<NSNumber> {
    logger.log("xctest process (\(processIdentifier)) died prematurely, checking for crash log for \(crashLogWaitTime) seconds")
    return
      XCTestProcess.crashLogs(forTerminationOfProcessIdentifier: processIdentifier, since: startDate, crashLogCommands: crashLogCommands, crashLogWaitTime: crashLogWaitTime, queue: queue)
      .rephraseFailure("xctest process (\(processIdentifier)) exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports")
      .onQueue(
        queue,
        fmap: { info -> FBFuture<AnyObject> in
          let rawLog = (try? info.loadRawCrashLogString()) ?? ""
          return FBFuture(error: XCTestProcessError.crashed(info: String(describing: info), rawLog: rawLog))
        }
      )
      .retyped(FBFuture<NSNumber>.self)
  }

  private static func crashLogs(forTerminationOfProcessIdentifier processIdentifier: pid_t, since sinceDate: Date, crashLogCommands: any CrashLogCommands, crashLogWaitTime: TimeInterval, queue: DispatchQueue) -> FBFuture<CrashLogInfo> {
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      CrashLogInfo.predicateForCrashLogs(withProcessID: processIdentifier),
      CrashLogInfo.predicateNewer(thanDate: sinceDate),
    ])

    let notify: FBFuture<CrashLogInfo> = fbFutureFromAsync {
      try await crashLogCommands.notifyOfCrash(matching: predicate)
    }
    return
      notify.retyped(FBFuture<AnyObject>.self)
      .onQueue(
        queue, timeout: crashLogWaitTime,
        handler: {
          FBFuture<AnyObject>(error: XCTestProcessError.crashLogTimedOut(processIdentifier: processIdentifier))
        }
      )
      .retyped(FBFuture<CrashLogInfo>.self)
  }
}
