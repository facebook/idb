/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import FBControlCore
import Foundation
import XCTestBootstrap

public protocol XCTestDescriptor: AnyObject {
  var url: URL { get }
  var name: String { get }
  var testBundleID: String { get }
  var architectures: Set<String> { get }
  var testBundle: FBBundleDescriptor { get }
  func setup(with request: XCTestRunRequest, target: any FBiOSTarget) -> FBFuture<NSNull>
  func testConfig(withRunRequest request: XCTestRunRequest, testApps: TestApplicationsPair, logDirectoryPath: String?, logger: FBControlCoreLogger) async throws -> IDBAppHostedTestConfiguration
  func testAppPair(for request: XCTestRunRequest, target: any FBiOSTarget) async throws -> TestApplicationsPair
}

public extension XCTestDescriptor {
  func setupAsync(with request: XCTestRunRequest, target: any FBiOSTarget) async throws {
    try await bridgeFBFutureVoid(self.setup(with: request, target: target))
  }
}

// MARK: - XCTestBootstrapDescriptor

enum XCTestDescriptorError: Error {
  case uiTestMissingAppBundleID
  case appTestMissingBundleIDs
  case noTestHostApplication(requestDescription: String)
  case notADataConsumer(result: String)
}

extension XCTestDescriptorError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .uiTestMissingAppBundleID:
      return "Request for UI Test, but no app_bundle_id provided"
    case .appTestMissingBundleIDs:
      return "Request for Application Test, but no app_bundle_id or test_host_app_bundle_id provided"
    case let .noTestHostApplication(requestDescription):
      return "Cannot build a test configuration for \(requestDescription), no test host application was resolved"
    case let .notADataConsumer(result):
      return "Expected a data consumer for the mirrored test process output, got \(result)"
    }
  }
}

final class XCTestBootstrapDescriptor: XCTestDescriptor, CustomStringConvertible {

  public let url: URL
  public let name: String
  public let testBundle: FBBundleDescriptor
  private var targetAuxillaryDirectory: String = ""

  public var testBundleID: String {
    testBundle.identifier
  }

  public var architectures: Set<String> {
    guard let arch = testBundle.binary?.architectures else { return [] }
    return Set(arch.map(\.rawValue))
  }

  public init(url: URL, name: String, testBundle: FBBundleDescriptor) {
    self.url = url
    self.name = name
    self.testBundle = testBundle
  }

  public var description: String {
    "xctestbootstrap descriptor for \(url) \(name) \(testBundle)"
  }

  // MARK: - Private

  private static func killAllRunningApplications(_ target: any FBiOSTarget) -> FBFuture<NSNull> {
    let future: FBFuture<NSNull> = fbFutureFromAsync {
      let running = try await target.application.running()
      try await Array(running.keys).concurrentForEachThrowingFirstError { bundleID in
        try await target.application.kill(bundleID: bundleID)
      }
      return NSNull()
    }
    return future
  }

  // MARK: - XCTestDescriptor

  public func setup(with request: XCTestRunRequest, target: any FBiOSTarget) -> FBFuture<NSNull> {
    targetAuxillaryDirectory = target.auxillaryDirectory
    if request.isLogicTest {
      return FBFuture<NSNull>.empty()
    }
    return XCTestBootstrapDescriptor.killAllRunningApplications(target).mapReplace(NSNull()).retyped(FBFuture<NSNull>.self)
  }

  public func testAppPair(for request: XCTestRunRequest, target: any FBiOSTarget) async throws -> TestApplicationsPair {
    if request.isLogicTest {
      return TestApplicationsPair(applicationUnderTest: nil, testHostApp: nil)
    }
    if request.isUITest {
      guard let testTargetAppBundleID = request.testTargetAppBundleID else {
        throw XCTestDescriptorError.uiTestMissingAppBundleID
      }
      let testHostBundleID = request.testHostAppBundleID ?? "com.apple.Preferences"
      let testTargetApp = try await target.application.installed(bundleID: testTargetAppBundleID)
      let testHostApp = try await target.application.installed(bundleID: testHostBundleID)
      return TestApplicationsPair(applicationUnderTest: testTargetApp, testHostApp: testHostApp)
    }
    // App Test
    guard let bundleID = request.testHostAppBundleID else {
      throw XCTestDescriptorError.appTestMissingBundleIDs
    }
    let application = try await target.application.installed(bundleID: bundleID)
    return TestApplicationsPair(applicationUnderTest: nil, testHostApp: application)
  }

  public func testConfig(withRunRequest request: XCTestRunRequest, testApps: TestApplicationsPair, logDirectoryPath: String?, logger: FBControlCoreLogger) async throws -> IDBAppHostedTestConfiguration {
    guard let testHostApp = testApps.testHostApp else {
      throw XCTestDescriptorError.noTestHostApplication(requestDescription: String(describing: request))
    }
    var coverageConfig: CodeCoverageConfiguration?
    if request.coverageRequest.collect {
      let coverageDirName = "coverage_\(UUID().uuidString)"
      let coverageDirPath = (targetAuxillaryDirectory as NSString).appendingPathComponent(coverageDirName)
      try FileManager.default.createDirectory(atPath: coverageDirPath, withIntermediateDirectories: true, attributes: nil)
      coverageConfig = CodeCoverageConfiguration(
        directory: coverageDirPath,
        format: request.coverageRequest.format,
        enableContinuousCoverageCollection: request.coverageRequest.shouldEnableContinuousCoverageCollection
      )
    }

    let applicationLaunchConfiguration = try await buildAppLaunchConfig(
      bundleID: testHostApp.bundle.identifier,
      environment: request.environment,
      arguments: request.arguments,
      logger: logger,
      processLogDirectory: logDirectoryPath,
      waitForDebugger: request.waitForDebugger
    )
    let testLaunchConfig = TestLaunchConfiguration(
      testBundle: testBundle,
      applicationLaunchConfiguration: applicationLaunchConfiguration,
      testHostBundle: testApps.testHostApp?.bundle,
      timeout: request.testTimeout?.doubleValue ?? 0,
      initializeUITesting: request.isUITest,
      useXcodebuild: false,
      testsToRun: request.testsToRun,
      testsToSkip: request.testsToSkip,
      targetApplicationBundle: testApps.applicationUnderTest?.bundle,
      xcTestRunProperties: nil,
      resultBundlePath: nil,
      reportActivities: request.reportActivities,
      coverageDirectoryPath: coverageConfig?.coverageDirectory,
      enableContinuousCoverageCollection: coverageConfig?.shouldEnableContinuousCoverageCollection ?? false,
      logDirectoryPath: logDirectoryPath,
      reportResultBundle: request.collectResultBundle
    )
    return IDBAppHostedTestConfiguration(testLaunchConfiguration: testLaunchConfig, coverageConfiguration: coverageConfig)
  }
}

// MARK: - XCodebuildTestRunDescriptor

final class XCodebuildTestRunDescriptor: XCTestDescriptor, CustomStringConvertible {

  public let url: URL
  public let name: String
  public let testBundle: FBBundleDescriptor
  public let testHostBundle: FBBundleDescriptor
  private var targetAuxillaryDirectory: String = ""

  public var testBundleID: String {
    testBundle.identifier
  }

  public var architectures: Set<String> {
    guard let arch = testHostBundle.binary?.architectures else { return [] }
    return Set(arch.map(\.rawValue))
  }

  public init(url: URL, name: String, testBundle: FBBundleDescriptor, testHostBundle: FBBundleDescriptor) {
    self.url = url
    self.name = name
    self.testBundle = testBundle
    self.testHostBundle = testHostBundle
  }

  public var description: String {
    "xcodebuild descriptor for \(url) \(name) \(testBundle) \(testHostBundle)"
  }

  // MARK: - XCTestDescriptor

  public func setup(with request: XCTestRunRequest, target: any FBiOSTarget) -> FBFuture<NSNull> {
    targetAuxillaryDirectory = target.auxillaryDirectory
    return FBFuture<NSNull>.empty()
  }

  public func testAppPair(for request: XCTestRunRequest, target: any FBiOSTarget) async throws -> TestApplicationsPair {
    TestApplicationsPair(applicationUnderTest: nil, testHostApp: nil)
  }

  public func testConfig(withRunRequest request: XCTestRunRequest, testApps: TestApplicationsPair, logDirectoryPath: String?, logger: FBControlCoreLogger) async throws -> IDBAppHostedTestConfiguration {
    let resultBundleName = "resultbundle_\(UUID().uuidString)"
    let resultBundlePath = (targetAuxillaryDirectory as NSString).appendingPathComponent(resultBundleName)

    let properties = try XCTestRunFileReader.readContents(of: url, expandPlaceholderWithPath: targetAuxillaryDirectory)

    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: nil, stdErr: nil)
    let launchConfig = FBApplicationLaunchConfiguration(
      bundleID: "not.used.bundleId",
      bundleName: nil,
      arguments: request.arguments,
      environment: request.environment,
      waitForDebugger: request.waitForDebugger,
      io: io,
      launchMode: .failIfRunning
    )

    let testLaunchConfiguration = TestLaunchConfiguration(
      testBundle: testBundle,
      applicationLaunchConfiguration: launchConfig,
      testHostBundle: testHostBundle,
      timeout: 0,
      initializeUITesting: request.isUITest,
      useXcodebuild: true,
      testsToRun: request.testsToRun,
      testsToSkip: request.testsToSkip,
      targetApplicationBundle: nil,
      xcTestRunProperties: properties,
      resultBundlePath: resultBundlePath,
      reportActivities: request.reportActivities,
      coverageDirectoryPath: nil,
      enableContinuousCoverageCollection: false,
      logDirectoryPath: logDirectoryPath,
      reportResultBundle: request.collectResultBundle
    )

    return IDBAppHostedTestConfiguration(testLaunchConfiguration: testLaunchConfiguration, coverageConfiguration: nil)
  }
}

// MARK: - Private Helper

private func buildAppLaunchConfig(bundleID: String, environment: [String: String], arguments: [String], logger: FBControlCoreLogger, processLogDirectory: String?, waitForDebugger: Bool) async throws -> FBApplicationLaunchConfiguration {
  let stdOutConsumer = FBLoggingDataConsumer(logger: logger)
  let stdErrConsumer = FBLoggingDataConsumer(logger: logger)

  guard let processLogDirectory else {
    return applicationLaunchConfiguration(bundleID: bundleID, environment: environment, arguments: arguments, waitForDebugger: waitForDebugger, stdOut: stdOutConsumer, stdErr: stdErrConsumer)
  }

  // Both mirrors are created before either is awaited, so the two file writers are opened concurrently.
  let mirrorLogger = XCTestLogger.defaultLogger(inDirectory: processLogDirectory)
  let stdOutFuture = mirrorLogger.logConsumption(of: stdOutConsumer, toFileNamed: "test_process_stdout.out", logger: logger)
  let stdErrFuture = mirrorLogger.logConsumption(of: stdErrConsumer, toFileNamed: "test_process_stderr.err", logger: logger)

  let stdOut = try await mirroredConsumer(stdOutFuture)
  let stdErr = try await mirroredConsumer(stdErrFuture)
  return applicationLaunchConfiguration(bundleID: bundleID, environment: environment, arguments: arguments, waitForDebugger: waitForDebugger, stdOut: stdOut, stdErr: stdErr)
}

private func mirroredConsumer(_ future: FBFuture<AnyObject>) async throws -> FBDataConsumer {
  let result = try await bridgeFBFuture(future)
  guard let consumer = result as? FBDataConsumer else {
    throw XCTestDescriptorError.notADataConsumer(result: String(describing: result))
  }
  return consumer
}

private func applicationLaunchConfiguration(bundleID: String, environment: [String: String], arguments: [String], waitForDebugger: Bool, stdOut: FBDataConsumer, stdErr: FBDataConsumer) -> FBApplicationLaunchConfiguration {
  let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(
    stdIn: nil,
    stdOut: FBProcessOutput<AnyObject>(for: stdOut),
    stdErr: FBProcessOutput<AnyObject>(for: stdErr)
  )
  return FBApplicationLaunchConfiguration(
    bundleID: bundleID,
    bundleName: nil,
    arguments: arguments,
    environment: environment,
    waitForDebugger: waitForDebugger,
    io: io,
    launchMode: .relaunchIfRunning
  )
}
