/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let bundleReadyTimeout: TimeInterval = 60
private let crashCheckWaitLimit: TimeInterval = 120

/**
 Connects to the test bundle over testmanagerd and runs the test plan to completion.

 The orchestration and crash diagnosis run on Swift `async`/`await`. The DTX transport, the private
 XCTest `_XCT_*` callback surface, and the `NSInvocation` message forwarding stay in the Objective-C
 `FBTestBundleDTXConnection`, which this type drives step by step.
 */
/// The ways a test-bundle connection can fail, as data rather than assembled strings.
enum FBTestBundleConnectionError: Error {
  case hostRelaunchedByOS(underlying: Error)
  case hostStalled(processIdentifier: pid_t, stackshot: String)
  case hostCrashed(crashLog: String)
  case connectionLost(message: String)
  case processStillRunning(processIdentifier: pid_t)
  case unexpectedCrashLookupResult(processIdentifier: pid_t)
}

extension FBTestBundleConnectionError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .hostRelaunchedByOS:
      return "Error while establishing connection to test bundle: Running test host application pid is different from the pid launched and set up to execute the tests. The host application is likely to have crashed during startup and been relaunched by iOS."
    case let .hostStalled(processIdentifier, stackshot):
      return "Could not connect to test bundle, but host application process \(processIdentifier) is still alive and busy/stalled: \(stackshot)"
    case let .hostCrashed(crashLog):
      return "Test Bundle/HostApp Crashed: \(crashLog)"
    case let .connectionLost(message):
      return message
    case let .processStillRunning(processIdentifier):
      return "The Process for \(processIdentifier) is not crashed as it is running"
    case let .unexpectedCrashLookupResult(processIdentifier):
      return "Crash log lookup for pid \(processIdentifier) returned an unexpected result"
    }
  }
}

final class FBTestBundleConnection {

  private let context: FBTestManagerContext
  private let target: any FBiOSTarget & ApplicationCommands & CrashLogCommands
  private let socket: Int32
  private let interface: NSObject
  private let testHostApplication: FBLaunchedApplication
  private let requestQueue: DispatchQueue
  private let logger: FBControlCoreLogger

  init(
    context: FBTestManagerContext,
    target: any FBiOSTarget & ApplicationCommands & CrashLogCommands,
    socket: Int32,
    interface: NSObject,
    testHostApplication: FBLaunchedApplication,
    requestQueue: DispatchQueue,
    logger: FBControlCoreLogger
  ) {
    self.context = context
    self.target = target
    self.socket = socket
    self.interface = interface
    self.testHostApplication = testHostApplication
    self.requestQueue = requestQueue
    self.logger = logger
  }

  func connectAndRun() async throws {
    logger.log("Connecting Test Bundle")
    let core = FBTestBundleDTXConnection(
      context: context,
      target: target,
      socket: socket,
      interface: interface,
      request: requestQueue,
      logger: logger
    )
    try await withFBFutureContext(core.connect()) { _ in
      do {
        try await bridgeFBFutureVoid(core.setupAndStartSession())
        try await bridgeFBFutureVoid(core.waitForBundleReady())
      } catch {
        throw await self.diagnosedConnectionError(from: error)
      }
      core.startExecutingTestPlan()
      try await bridgeFBFutureVoid(core.waitForBundleDisconnected())
      if core.testPlanCompleted {
        self.logger.log("Bundle disconnected, with the test plan completed. Bundle exited successfully.")
      } else {
        self.logger.log("Bundle disconnected, but test plan has not completed. This could mean a crash has occurred")
        throw await self.crashLogOrNotFoundError(description: "Lost connection to test process, but could not find a crash log")
      }
    }
  }

  // MARK: - Diagnosis (replaces the FBTestHostProcessQuery / FBTestHostCrashLogQuery bridges)

  /// Always produces an error explaining the connection failure as precisely as possible.
  private func diagnosedConnectionError(from error: Error) async -> Error {
    let bundleID = context.testHostLaunchConfiguration.bundleID
    let runningPid: pid_t
    do {
      runningPid = try await target.processID(forBundleID: bundleID)
    } catch {
      // No running host process — it likely crashed during startup but lived long enough to avoid a
      // relaunch. Look for a crash log.
      return await crashLogOrNotFoundError(description: "Error while establishing connection to test bundle: The host application is likely to have crashed during startup, but could not find a crash log.")
    }
    let expectedPid = testHostApplication.processIdentifier
    if runningPid != expectedPid {
      // iOS sometimes relaunches a host that crashed very early as a vanilla process that idb cannot
      // drive, so there is no bundle to connect to.
      return FBTestBundleConnectionError.hostRelaunchedByOS(underlying: error)
    }
    // Host process is alive — sample its stack for the error message.
    if let stackshot = (try? await bridgeFBFuture(FBProcessFetcher.performSampleStackshot(forProcessIdentifier: expectedPid, queue: target.workQueue))) as? String {
      return FBTestBundleConnectionError.hostStalled(processIdentifier: expectedPid, stackshot: stackshot)
    }
    return error
  }

  private func crashLogOrNotFoundError(description notFound: String) async -> Error {
    if let crashLog = try? await findCrashedProcessLog() {
      return FBTestBundleConnectionError.hostCrashed(crashLog: String(describing: crashLog))
    }
    return FBTestBundleConnectionError.connectionLost(message: notFound)
  }

  private func findCrashedProcessLog() async throws -> FBCrashLog {
    let bundleID = context.testHostLaunchConfiguration.bundleID
    // If the host process is still running it has not crashed.
    if let runningPid = try? await target.processID(forBundleID: bundleID) {
      throw FBTestBundleConnectionError.processStillRunning(processIdentifier: runningPid)
    }
    var crashWaitTimeout = crashCheckWaitLimit
    if let env = ProcessInfo.processInfo.environment["FBXCTEST_CRASH_WAIT_TIMEOUT"] {
      crashWaitTimeout = TimeInterval((env as NSString).floatValue)
    }
    let pid = testHostApplication.processIdentifier
    let predicate = FBCrashLogInfo.predicateForCrashLogs(withProcessID: pid)
    // CrashLogCommands.notifyOfCrash(matching:) has no timeout, so bound it with FBFuture's
    // timeout the way the old FBTestHostCrashLogQuery caller did.
    let future = fbFutureFromAsync { try await self.target.notifyOfCrash(matching: predicate) }
    let timed = future.timeout(crashWaitTimeout, waitingFor: "Getting crash log for process with pid \(pid), bundle ID: \(bundleID)")
    guard let info = try await bridgeFBFuture(timed) as? FBCrashLogInfo else {
      throw FBTestBundleConnectionError.unexpectedCrashLookupResult(processIdentifier: pid)
    }
    return try info.obtainCrashLog()
  }
}
