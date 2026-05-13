/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation
@preconcurrency import XCTestBootstrap

// swiftlint:disable force_unwrapping

private let testmanagerdSimSockTimeout: TimeInterval = 5
private let simSockEnvKey = "TESTMANAGERD_SIM_SOCK"

@objc(FBSimulatorXCTestCommands)
public final class FBSimulatorXCTestCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var isRunningXcodeBuildOperation: Bool = false

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorXCTestCommands {
    return FBSimulatorXCTestCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBXCTestCommands (legacy FBFuture entry points)

  @objc(runTestWithLaunchConfiguration:reporter:logger:)
  public func runTest(withLaunchConfiguration testLaunchConfiguration: FBTestLaunchConfiguration, reporter: AnyObject, logger: any FBControlCoreLogger) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await runTestAsync(launchConfiguration: testLaunchConfiguration, reporter: reporter, logger: logger)
      return NSNull()
    }
  }

  // FBFutureContext APIs cannot be expressed natively in async/await producer
  // form (only the consumer side `withFBFutureContext` exists). Keep the
  // existing FBFuture/FBFutureContext implementation for now.
  @objc(transportForTestManagerService)
  public func transportForTestManagerService() -> FBFutureContext<NSNumber> {
    guard let simulator = self.simulator else {
      return
        FBSimulatorError
        .describe("Simulator is deallocated")
        .failFutureContext() as! FBFutureContext<NSNumber>
    }

    return
      (unsafeBitCast(testManagerDaemonSocketPath(), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.asyncQueue,
        fmap: { (pathObj: Any) -> FBFuture<AnyObject> in
          let testManagerSocketString = pathObj as! String
          let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
          if socketFD == -1 {
            return FBSimulatorError.describe("Unable to create a unix domain socket").failFuture()
          }
          if !FileManager.default.fileExists(atPath: testManagerSocketString) {
            close(socketFD)
            return FBSimulatorError.describe("Simulator indicated unix domain socket for testmanagerd at path \(testManagerSocketString), but no file was found at that path.").failFuture()
          }

          let testManagerSocketCStr = testManagerSocketString.utf8CString
          if testManagerSocketCStr.count - 1 >= 0x68 {
            close(socketFD)
            return FBSimulatorError.describe("Unix domain socket path for simulator testmanagerd service '\(testManagerSocketString)' is too big to fit in sockaddr_un.sun_path").failFuture()
          }

          var remote = sockaddr_un()
          remote.sun_family = sa_family_t(AF_UNIX)
          testManagerSocketCStr.withUnsafeBufferPointer { buffer in
            withUnsafeMutablePointer(to: &remote.sun_path) { sunPathPtr in
              sunPathPtr.withMemoryRebound(to: CChar.self, capacity: Int(buffer.count)) { dest in
                _ = memcpy(dest, buffer.baseAddress!, buffer.count)
              }
            }
          }
          let length = socklen_t(MemoryLayout<sa_family_t>.size + MemoryLayout.size(ofValue: remote.sun_len) + strlen(testManagerSocketString))
          let connectResult = withUnsafePointer(to: &remote) { remotePtr in
            remotePtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
              connect(socketFD, sockaddrPtr, length)
            }
          }
          if connectResult == -1 {
            close(socketFD)
            return FBSimulatorError.describe("Failed to connect to testmangerd socket").failFuture()
          }
          return FBFuture(result: NSNumber(value: socketFD))
        }
      )
      .onQueue(
        simulator.asyncQueue,
        contextualTeardown: { (socketNumber: Any, _: FBFutureState) -> FBFuture<NSNull> in
          close(Int32((socketNumber as! NSNumber).intValue))
          return FBFuture<NSNull>.empty()
        })) as! FBFutureContext<NSNumber>
  }

  // MARK: - FBXCTestExtendedCommands (legacy FBFuture entry points)

  @objc(listTestsForBundleAtPath:timeout:withAppAtPath:)
  public func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await listTestsAsync(forBundleAtPath: bundlePath, timeout: timeout, withAppAtPath: appPath) as NSArray
    }
  }

  @objc
  public func extendedTestShim() -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await extendedTestShimAsync() as NSString
    }
  }

  @objc
  public var xctestPath: String {
    return (FBXcodeConfiguration.developerDirectory as NSString)
      .appendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest")
  }

  // MARK: - Async

  fileprivate func runTestAsync(launchConfiguration: FBTestLaunchConfiguration, reporter: AnyObject, logger: any FBControlCoreLogger) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator is deallocated").build()
    }
    // swiftlint:disable:next force_cast
    let typedReporter = reporter as! any FBXCTestReporter

    if !launchConfiguration.shouldUseXcodebuild {
      try await runTestAsync(with: launchConfiguration, reporter: typedReporter, logger: logger, workingDirectory: simulator.auxillaryDirectory)
      return
    }

    if isRunningXcodeBuildOperation {
      throw FBSimulatorError.describe("Cannot Start Test Manager with Configuration \(launchConfiguration) as it is already running").build()
    }

    _ = try await bridgeFBFuture(
      FBXcodeBuildOperation.terminateAbandonedXcodebuildProcesses(
        forUDID: simulator.udid,
        processFetcher: FBProcessFetcher(),
        queue: simulator.workQueue,
        logger: logger))

    isRunningXcodeBuildOperation = true
    defer { isRunningXcodeBuildOperation = false }

    let subprocess = try await startTestAsync(with: launchConfiguration, logger: logger)
    try await bridgeFBFutureVoid(
      FBXcodeBuildOperation.confirmExit(ofXcodebuildOperation: subprocess, configuration: launchConfiguration, reporter: typedReporter, target: simulator, logger: logger))
  }

  fileprivate func listTestsAsync(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) async throws -> [String] {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator is deallocated").build()
    }

    let bundleDescriptor = try FBBundleDescriptor.bundleWithFallbackIdentifier(fromPath: bundlePath)
    let architectures = Set((bundleDescriptor.binary?.architectures ?? []).map(\.rawValue))
    let configuration = FBListTestConfiguration.configuration(
      withEnvironment: [:],
      workingDirectory: simulator.auxillaryDirectory,
      testBundlePath: bundlePath,
      runnerAppPath: appPath,
      waitForDebugger: false,
      timeout: timeout,
      architectures: architectures)

    return try await bridgeFBFutureArray(
      FBListTestStrategy(target: unsafeBitCast(simulator, to: (any FBiOSTarget & AsyncProcessSpawnCommands & AsyncXCTestExtendedCommands).self), configuration: configuration, logger: simulator.logger!)
        .listTests())
  }

  fileprivate func extendedTestShimAsync() async throws -> String {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator is deallocated").build()
    }
    let shimConfig = try await bridgeFBFuture(FBXCTestShimConfiguration.sharedShimConfiguration(with: simulator.logger))
    return shimConfig.iOSSimulatorTestShimPath
  }

  // MARK: - Private

  private func runTestAsync(with testLaunchConfiguration: FBTestLaunchConfiguration, reporter: any FBXCTestReporter, logger: any FBControlCoreLogger, workingDirectory: String?) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator is deallocated").build()
    }

    if simulator.state != .booted {
      throw FBSimulatorError.describe("Simulator must be booted to run tests").build()
    }

    try await bridgeFBFutureVoid(
      FBManagedTestRunStrategy.runToCompletion(
        withTarget: unsafeBitCast(simulator, to: (any FBiOSTarget & FBXCTestExtendedCommands & FBApplicationCommands).self),
        configuration: testLaunchConfiguration,
        codesign: FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid
          ? FBCodesignProvider.codeSignCommand(withIdentityName: "-", logger: simulator.logger)
          : nil,
        workingDirectory: simulator.auxillaryDirectory,
        reporter: reporter,
        logger: logger))
  }

  private func testManagerDaemonSocketPath() -> FBFuture<NSString> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator is deallocated").build())
    }

    return
      (FBFuture<AnyObject>.onQueue(
        simulator.asyncQueue,
        resolveUntil: { [weak self] () -> FBFuture<AnyObject> in
          guard let self, let simulator = self.simulator else {
            return FBSimulatorError.describe("Simulator is deallocated").failFuture()
          }
          let socketPath: String?
          var getenvError: NSError?
          do {
            socketPath = try simulator.device.getenv(simSockEnvKey)
          } catch {
            socketPath = nil
            getenvError = error as NSError
          }
          if socketPath == nil || socketPath!.isEmpty {
            return
              FBSimulatorError
              .describe("Failed to get \(simSockEnvKey) from simulator environment")
              .caused(by: getenvError)
              .failFuture()
          }
          return FBFuture(result: socketPath! as NSString)
        }
      )
      .timeout(testmanagerdSimSockTimeout, waitingFor: "\(simSockEnvKey) to become available in the simulator environment")) as! FBFuture<NSString>
  }

  private func startTestAsync(with configuration: FBTestLaunchConfiguration, logger: any FBControlCoreLogger) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator is deallocated").build()
    }

    let filePath = try FBXcodeBuildOperation.createXCTestRunFile(at: simulator.auxillaryDirectory, fromConfiguration: configuration)
    let xcodeBuildPath = try FBXcodeBuildOperation.xcodeBuildPath()

    let shimConfig = try await bridgeFBFuture(FBXCTestShimConfiguration.sharedShimConfiguration(with: simulator.logger))
    return try await bridgeFBFuture(
      FBXcodeBuildOperation.operation(
        withUDID: simulator.udid,
        configuration: configuration,
        xcodeBuildPath: xcodeBuildPath,
        testRunFilePath: filePath,
        simDeviceSet: simulator.customDeviceSetPath,
        macOSTestShimPath: shimConfig.macOSTestShimPath,
        queue: simulator.workQueue,
        logger: logger.withName("xcodebuild")))
  }
}

// MARK: - FBSimulator+AsyncXCTestExtendedCommands

extension FBSimulator: AsyncXCTestExtendedCommands {

  public func runTest(
    launchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws {
    try await xctestExtendedCommands().runTestAsync(launchConfiguration: launchConfiguration, reporter: reporter, logger: logger)
  }

  public func listTests(
    forBundleAtPath bundlePath: String,
    timeout: TimeInterval,
    withAppAtPath appPath: String?
  ) async throws -> [String] {
    try await xctestExtendedCommands().listTestsAsync(forBundleAtPath: bundlePath, timeout: timeout, withAppAtPath: appPath)
  }

  public func extendedTestShim() async throws -> String {
    try await xctestExtendedCommands().extendedTestShimAsync()
  }

  public func withTransportForTestManagerService<R>(
    body: (NSNumber) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(xctestExtendedCommands().transportForTestManagerService(), body: body)
  }

  public var xctestPath: String {
    do {
      return try xctestExtendedCommands().xctestPath
    } catch {
      return ""
    }
  }
}

// MARK: - FBSimulator+FBXCTestExtendedCommands

extension FBSimulator: FBXCTestExtendedCommands {

  @objc(runTestWithLaunchConfiguration:reporter:logger:)
  public func runTest(withLaunchConfiguration testLaunchConfiguration: FBTestLaunchConfiguration, reporter: AnyObject, logger: any FBControlCoreLogger) -> FBFuture<NSNull> {
    do {
      return try xctestExtendedCommands().runTest(withLaunchConfiguration: testLaunchConfiguration, reporter: reporter, logger: logger)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(listTestsForBundleAtPath:timeout:withAppAtPath:)
  public func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) -> FBFuture<NSArray> {
    do {
      return try xctestExtendedCommands().listTests(forBundleAtPath: bundlePath, timeout: timeout, withAppAtPath: appPath)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func extendedTestShim() -> FBFuture<NSString> {
    do {
      return try xctestExtendedCommands().extendedTestShim()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(transportForTestManagerService)
  public func transportForTestManagerService() -> FBFutureContext<NSNumber> {
    do {
      return try xctestExtendedCommands().transportForTestManagerService()
    } catch {
      return FBFutureContext(error: error)
    }
  }
}
