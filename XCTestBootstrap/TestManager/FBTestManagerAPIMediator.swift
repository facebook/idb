/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/**
 A simplified re-implementation of Apple's _IDETestManagerAPIMediator class.
 This class 'takes over' after an Application Process has been started, mediating between the host,
 the `testmanagerd` daemon, and the test runner.

 The orchestration and application lifecycle operations run on Swift `async`/`await` over
 `ApplicationCommands`. The private XCTest `XCTestManager_IDEInterface` callback surface that the
 test runner communicates with stays in Objective-C in `FBTestManagerAPIMediatorIDEInterface`, which
 forwards application launch/termination requests back to this type.
 */
@objc(FBTestManagerAPIMediator)
public final class FBTestManagerAPIMediator: NSObject, @unchecked Sendable {

  private static let defaultTestTimeout: TimeInterval = 60 * 60 // 1 hour.

  // MARK: - Properties

  private let context: FBTestManagerContext
  private let target: any FBiOSTarget
  private let asyncTarget: any ApplicationCommands
  private let asyncXCTestTarget: any XCTestExtendedCommands
  private let reporter: FBXCTestReporter
  private let logger: FBControlCoreLogger
  private let requestQueue: DispatchQueue

  private let tokenLock = NSLock()
  private var tokenToLaunchedApp: [NSNumber: FBLaunchedApplication] = [:]

  private lazy var ideInterface = FBTestManagerAPIMediatorIDEInterface(mediator: self, context: context, reporter: reporter, logger: logger)

  // MARK: - Initializers

  /**
   Performs the entire process of test execution: connecting to `testmanagerd`, the test bundle and
   the test execution itself. The returned future resolves when test execution has fully completed,
   or an error occurred with the execution. Test failures are not represented as an error.
   */
  public static func connectAndRunUntilCompletion(
    with context: FBTestManagerContext,
    target: any FBiOSTarget,
    reporter: FBXCTestReporter,
    logger: FBControlCoreLogger
  ) -> FBFuture<NSNull> {
    let mediator = FBTestManagerAPIMediator(context: context, target: target, reporter: reporter, logger: logger)
    return fbFutureFromAsync {
      try await mediator.connectAndRunUntilCompletion()
      return NSNull()
    }
  }

  private init(
    context: FBTestManagerContext,
    target: any FBiOSTarget,
    reporter: FBXCTestReporter,
    logger: FBControlCoreLogger
  ) {
    self.context = context
    self.target = target
    // FBSimulator, FBDevice and FBMacDevice all conform to ApplicationCommands in addition to
    // the legacy FBApplicationCommands declared in this type's signature.
    // swiftlint:disable:next force_cast
    self.asyncTarget = target as! any ApplicationCommands
    // swiftlint:disable:next force_cast
    self.asyncXCTestTarget = target as! any XCTestExtendedCommands
    self.reporter = reporter
    self.logger = logger
    self.requestQueue = DispatchQueue(label: "com.facebook.xctestboostrap.mediator")
    super.init()
  }

  // MARK: - Orchestration

  private func connectAndRunUntilCompletion() async throws {
    let timeout = context.timeout <= 0 ? Self.defaultTestTimeout : context.timeout
    let result: Result<Void, Error>
    do {
      let launchedApplication = try await asyncTarget.launchApplication(context.testHostLaunchConfiguration)
      do {
        if context.testHostLaunchConfiguration.waitForDebugger {
          reporter.processWaitingForDebugger(withProcessIdentifier: launchedApplication.processIdentifier)
          try await bridgeFBFutureVoid(FBProcessFetcher.waitForDebuggerToAttachAndContinue(for: launchedApplication.processIdentifier))
        }
        try await runUntilCompletion(launchedApplication: launchedApplication, timeout: timeout)
        result = .success(())
      } catch {
        result = .failure(error)
      }
      // Mirror the contextual teardown of the test host: terminate it.
      _ = try? await launchedApplication.terminate()
    } catch {
      result = .failure(error)
    }

    reporter.processUnderTestDidExit()
    if case let .failure(error) = result {
      logger.log("Test Execution finished in error \(error)")
      reporter.didCrashDuringTest(error)
    }
    try result.get()
  }

  private func runUntilCompletion(launchedApplication: FBLaunchedApplication, timeout: TimeInterval) async throws {
    let work: FBFuture<AnyObject> = fbFutureFromAsync { () -> AnyObject in
      // Open the testmanagerd transport over async and hand the socket down to the Objective-C
      // bundle connection (which no longer acquires the transport itself). The socket stays open
      // for the duration of the connection and is closed when this scope ends.
      try await self.asyncXCTestTarget.withTransportForTestManagerService { socket in
        let connection = FBTestBundleConnection(
          context: self.context,
          target: self.target,
          socket: socket.int32Value,
          interface: self.ideInterface,
          testHostApplication: launchedApplication,
          requestQueue: self.requestQueue,
          logger: self.logger
        )
        try await connection.connectAndRun()
      }
      // The bundle has disconnected at this point, but we also need to terminate any processes
      // spawned through `_XCT_launchProcessWithPath` and tear down the host application.
      try await self.terminateSpawnedProcesses()
      _ = try? await launchedApplication.terminate()
      return NSNull()
    }
    // The timeout is applied to the lifecycle of the entire application.
    let timed = work.onQueue(requestQueue, timeout: timeout) { () -> FBFuture<AnyObject> in
      self.logger.log("Timed out after \(timeout), attempting stack sample")
      return fbFutureFromAsync { () -> AnyObject in
        let stackshot = (try? await self.sampleStack(forProcessIdentifier: launchedApplication.processIdentifier)) ?? "<no stackshot>"
        try? await self.terminateSpawnedProcesses()
        throw FBXCTestError.describe("Waited \(timeout) seconds for process \(launchedApplication.processIdentifier) to terminate, but the host application process stalled: \(stackshot)").build()
      }
    }
    try await bridgeFBFutureVoid(timed)
  }

  private func sampleStack(forProcessIdentifier processIdentifier: pid_t) async throws -> String {
    let result: AnyObject = try await bridgeFBFuture(FBProcessFetcher.performSampleStackshot(forProcessIdentifier: processIdentifier, queue: requestQueue))
    return (result as? String) ?? ""
  }

  // MARK: - Spawned process token map (synchronous, lock-guarded)

  private func storeToken(_ token: NSNumber, launchedApplication: FBLaunchedApplication) {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    tokenToLaunchedApp[token] = launchedApplication
  }

  private func launchedApplication(forToken token: NSNumber) -> FBLaunchedApplication? {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    return tokenToLaunchedApp[token]
  }

  private func drainSpawnedApplications() -> [FBLaunchedApplication] {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    let apps = Array(tokenToLaunchedApp.values)
    tokenToLaunchedApp.removeAll()
    return apps
  }

  private func terminateSpawnedProcesses() async throws {
    let appsToKill = drainSpawnedApplications()
    if appsToKill.isEmpty {
      return
    }
    logger.log("Terminating processes spawned due to test bundle requests: \(appsToKill.map(\.bundleID))")
    for app in appsToKill {
      try await asyncTarget.killApplication(bundleID: app.bundleID)
    }
  }

  // MARK: - Application lifecycle (invoked by the IDE interface delegate)

  @objc(launchProcessForUITestWithToken:path:bundleID:arguments:environment:completion:)
  public func launchProcessForUITest(
    withToken token: NSNumber,
    path: String?,
    bundleID: String,
    arguments: [String],
    environment: [String: String],
    completion: @escaping @Sendable (Error?) -> Void
  ) {
    logger.log("Test process requested process launch with bundleID \(bundleID)")
    Task {
      do {
        let launchedApplication = try await self.launchUITestProcess(path: path, bundleID: bundleID, arguments: arguments, environment: environment)
        self.storeToken(token, launchedApplication: launchedApplication)
        completion(nil)
      } catch {
        completion(error)
      }
    }
  }

  @objc(terminateProcessForToken:completion:)
  public func terminateProcess(forToken token: NSNumber?, completion: @escaping @Sendable (Error?) -> Void) {
    logger.log("Test process requested process termination with token \(String(describing: token))")
    guard let token else {
      completion(NSError(domain: "XCTestIDEInterfaceErrorDomain", code: 0x1, userInfo: [NSLocalizedDescriptionKey: "API violation: token was nil."]))
      return
    }
    guard let app = launchedApplication(forToken: token) else {
      completion(NSError(domain: "XCTestIDEInterfaceErrorDomain", code: 0x2, userInfo: [NSLocalizedDescriptionKey: "Invalid or expired token: no matching operation was found."]))
      return
    }
    let bundleID = app.bundleID
    Task {
      do {
        try await self.asyncTarget.killApplication(bundleID: bundleID)
        completion(nil)
      } catch {
        completion(error)
      }
    }
  }

  private func launchUITestProcess(path: String?, bundleID: String, arguments: [String], environment: [String: String]) async throws -> FBLaunchedApplication {
    var targetEnvironment = context.testedApplicationAdditionalEnvironment
    for (key, value) in environment {
      targetEnvironment[key] = value
    }
    // swiftlint:disable force_cast
    let stdOut = FBProcessOutput(for: logger) as! FBProcessOutput<AnyObject>
    let stdErr = FBProcessOutput(for: logger) as! FBProcessOutput<AnyObject>
    // swiftlint:enable force_cast
    let processIO = FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: stdOut, stdErr: stdErr)
    let launch = FBApplicationLaunchConfiguration(
      bundleID: bundleID,
      bundleName: bundleID,
      arguments: arguments,
      environment: targetEnvironment,
      waitForDebugger: false,
      io: processIO,
      launchMode: .failIfRunning
    )
    return try await launchApplication(launch, atPath: path)
  }

  private func launchApplication(_ configuration: FBApplicationLaunchConfiguration, atPath path: String?) async throws -> FBLaunchedApplication {
    // If the bundle is already installed at the expected path, just launch it.
    if let installed = try? await asyncTarget.installedApplication(bundleID: configuration.bundleID), installed.bundle.path == path {
      return try await asyncTarget.launchApplication(configuration)
    }
    return try await installAndLaunchApplication(configuration, atPath: path)
  }

  private func installAndLaunchApplication(_ configuration: FBApplicationLaunchConfiguration, atPath path: String?) async throws -> FBLaunchedApplication {
    guard let path else {
      throw FBControlCoreError.describe("Could not install App-Under-Test \(configuration) as it is not installed and no path was provided").build()
    }
    if await isApplicationInstalled(bundleID: configuration.bundleID) {
      try await asyncTarget.uninstallApplication(bundleID: configuration.bundleID)
    }
    _ = try await asyncTarget.installApplication(atPath: path)
    return try await asyncTarget.launchApplication(configuration)
  }

  private func isApplicationInstalled(bundleID: String) async -> Bool {
    do {
      _ = try await asyncTarget.installedApplication(bundleID: bundleID)
      return true
    } catch {
      return false
    }
  }
}
