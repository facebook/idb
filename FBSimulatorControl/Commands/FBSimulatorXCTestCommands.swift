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

private let testmanagerdSimSockTimeout: TimeInterval = 5
private let simSockEnvKey = "TESTMANAGERD_SIM_SOCK"

/// The ways simulator test execution can fail, as data rather than assembled strings.
public enum FBSimulatorXCTestError: Error {
  case socketCreationFailed
  case socketFileMissing(path: String)
  case socketPathTooLong(path: String)
  case socketConnectionFailed
  case unexpectedReporter(reporterDescription: String)
  case testManagerAlreadyRunning(configurationDescription: String)
  case environmentVariableUnavailable(key: String, underlying: Error?)
}

extension FBSimulatorXCTestError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .socketCreationFailed:
      return "Unable to create a unix domain socket"
    case let .socketFileMissing(path):
      return "Simulator indicated unix domain socket for testmanagerd at path \(path), but no file was found at that path."
    case let .socketPathTooLong(path):
      return "Unix domain socket path for simulator testmanagerd service '\(path)' is too big to fit in sockaddr_un.sun_path"
    case .socketConnectionFailed:
      return "Failed to connect to testmangerd socket"
    case let .unexpectedReporter(reporterDescription):
      return "\(reporterDescription) is not an FBXCTestReporter"
    case let .testManagerAlreadyRunning(configurationDescription):
      return "Cannot Start Test Manager with Configuration \(configurationDescription) as it is already running"
    case let .environmentVariableUnavailable(key, _):
      return "Failed to get \(key) from simulator environment"
    }
  }
}

public final class FBSimulatorXCTestCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var isRunningXcodeBuildOperation: Bool = false

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorXCTestCommands {
    return FBSimulatorXCTestCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - testmanagerd transport

  /// Resolves the testmanagerd unix-domain socket, connects to it, and hands the socket fd to
  /// `body` for the duration of the call, closing it on exit.
  fileprivate func withTransportForTestManagerService<R>(body: (NSNumber) async throws -> R) async throws -> R {
    guard self.simulator != nil else {
      throw FBWeakTargetError.simulator
    }
    let socketPath = try await testManagerDaemonSocketPath()
    let socketFD = try Self.connectedTestManagerSocket(atPath: socketPath)
    defer { close(socketFD) }
    return try await body(NSNumber(value: socketFD))
  }

  private static func connectedTestManagerSocket(atPath testManagerSocketString: String) throws -> Int32 {
    let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    if socketFD == -1 {
      throw FBSimulatorXCTestError.socketCreationFailed
    }
    if !FileManager.default.fileExists(atPath: testManagerSocketString) {
      close(socketFD)
      throw FBSimulatorXCTestError.socketFileMissing(path: testManagerSocketString)
    }
    let testManagerSocketCStr = testManagerSocketString.utf8CString
    if testManagerSocketCStr.count - 1 >= 0x68 {
      close(socketFD)
      throw FBSimulatorXCTestError.socketPathTooLong(path: testManagerSocketString)
    }
    var remote = sockaddr_un()
    remote.sun_family = sa_family_t(AF_UNIX)
    testManagerSocketCStr.withUnsafeBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return
      }
      withUnsafeMutablePointer(to: &remote.sun_path) { sunPathPtr in
        sunPathPtr.withMemoryRebound(to: CChar.self, capacity: Int(buffer.count)) { dest in
          _ = memcpy(dest, baseAddress, buffer.count)
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
      throw FBSimulatorXCTestError.socketConnectionFailed
    }
    return socketFD
  }

  public var xctestPath: String {
    (FBXcodeConfiguration.developerDirectory as NSString)
      .appendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest")
  }

  // MARK: - Async

  fileprivate func runTest(launchConfiguration: FBTestLaunchConfiguration, reporter: AnyObject, logger: any FBControlCoreLogger) async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    // `XCTestCommands` lives in FBControlCore, which cannot see `FBXCTestReporter` in XCTestBootstrap,
    // so the reporter arrives type-erased and has to be recovered here.
    guard let typedReporter = reporter as? any FBXCTestReporter else {
      throw FBSimulatorXCTestError.unexpectedReporter(reporterDescription: String(describing: reporter))
    }

    if !launchConfiguration.shouldUseXcodebuild {
      try await runTest(with: launchConfiguration, reporter: typedReporter, logger: logger, workingDirectory: simulator.auxillaryDirectory)
      return
    }

    if isRunningXcodeBuildOperation {
      throw FBSimulatorXCTestError.testManagerAlreadyRunning(configurationDescription: String(describing: launchConfiguration))
    }

    _ = try await bridgeFBFuture(
      FBXcodeBuildOperation.terminateAbandonedXcodebuildProcesses(
        forUDID: simulator.udid,
        processFetcher: FBProcessFetcher(),
        queue: simulator.workQueue,
        logger: logger))

    isRunningXcodeBuildOperation = true
    defer { isRunningXcodeBuildOperation = false }

    let subprocess = try await startTest(with: launchConfiguration, logger: logger)
    try await bridgeFBFutureVoid(
      FBXcodeBuildOperation.confirmExit(ofXcodebuildOperation: subprocess, configuration: launchConfiguration, reporter: typedReporter, target: simulator, logger: logger))
  }

  fileprivate func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) async throws -> [String] {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
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
      FBListTestStrategy(target: simulator as any FBiOSTarget & ProcessSpawnCommands & XCTestExtendedCommands, configuration: configuration, logger: simulator.logger)
        .listTests())
  }

  fileprivate func extendedTestShim() async throws -> String {
    let shimConfig = try await FBXCTestShimConfiguration.sharedShimConfiguration()
    return shimConfig.iOSSimulatorTestShimPath
  }

  // MARK: - Private

  private func runTest(with testLaunchConfiguration: FBTestLaunchConfiguration, reporter: any FBXCTestReporter, logger: any FBControlCoreLogger, workingDirectory: String?) async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }

    if simulator.state != .booted {
      throw FBSimulatorStateError.notBooted(operation: "run tests", state: simulator.stateString.rawValue)
    }

    try await FBManagedTestRunStrategy.runToCompletion(
      withTarget: simulator,
      configuration: testLaunchConfiguration,
      codesign: FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid
        ? FBCodesignProvider.codeSignCommand(withIdentityName: "-", logger: simulator.logger)
        : nil,
      workingDirectory: simulator.auxillaryDirectory,
      reporter: reporter,
      logger: logger)
  }

  // Internal so the poll can be unit-tested with a getenv device double.
  func testManagerDaemonSocketPath() async throws -> String {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let deadline = Date().addingTimeInterval(testmanagerdSimSockTimeout)
    var lastError: NSError?
    while true {
      do {
        let socketPath = try simulator.device.getenv(simSockEnvKey)
        if !socketPath.isEmpty {
          return socketPath
        }
      } catch {
        lastError = error as NSError
      }
      if Date() >= deadline {
        throw FBSimulatorXCTestError.environmentVariableUnavailable(key: simSockEnvKey, underlying: lastError)
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  private func startTest(with configuration: FBTestLaunchConfiguration, logger: any FBControlCoreLogger) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }

    let filePath = try FBXcodeBuildOperation.createXCTestRunFile(at: simulator.auxillaryDirectory, fromConfiguration: configuration)
    let xcodeBuildPath = try FBXcodeBuildOperation.xcodeBuildPath()

    let shimConfig = try await FBXCTestShimConfiguration.sharedShimConfiguration()
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

// MARK: - FBSimulator+XCTestExtendedCommands

extension FBSimulator: XCTestExtendedCommands {

  public func runTest(
    launchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws {
    try await xctestExtended.runTest(launchConfiguration: launchConfiguration, reporter: reporter, logger: logger)
  }

  public func listTests(
    forBundleAtPath bundlePath: String,
    timeout: TimeInterval,
    withAppAtPath appPath: String?
  ) async throws -> [String] {
    try await xctestExtended.listTests(forBundleAtPath: bundlePath, timeout: timeout, withAppAtPath: appPath)
  }

  public func extendedTestShim() async throws -> String {
    try await xctestExtended.extendedTestShim()
  }

  public func withTransportForTestManagerService<R>(
    body: (NSNumber) async throws -> R
  ) async throws -> R {
    try await xctestExtended.withTransportForTestManagerService(body: body)
  }

  public var xctestPath: String {
    xctestExtended.xctestPath
  }
}
