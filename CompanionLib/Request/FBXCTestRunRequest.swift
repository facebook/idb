/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

private let FBLogicTestTimeout: TimeInterval = 60 * 60

// MARK: - FBXCTestRunRequest

public enum FBXCTestRunRequestError: Error {
  case notExactlyOneTest(count: Int)
  case testDescriptorNotFound
  case logicTestsUnsupported(targetDescription: String)
  case xctestUnsupported(targetDescription: String)
  case testsToSkipUnsupported(testsToSkip: [String])
  case multipleTestsToRun(testsToRun: [String])
}

extension FBXCTestRunRequestError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .notExactlyOneTest(count):
      return "Expected exactly one test in the xctestrun file, got: \(count)"
    case .testDescriptorNotFound:
      return "Could not find test descriptor"
    case let .logicTestsUnsupported(targetDescription):
      return "Target \(targetDescription) does not support process spawning and extended xctest commands, cannot run logic tests"
    case let .xctestUnsupported(targetDescription):
      return "Target \(targetDescription) does not support xctest commands, cannot run tests"
    case let .testsToSkipUnsupported(testsToSkip):
      return "'Tests to Skip' \(FBCollectionInformation.oneLineDescription(from: testsToSkip)) provided, but Logic Tests do not support this."
    case let .multipleTestsToRun(testsToRun):
      return "More than one 'Tests to Run' \(FBCollectionInformation.oneLineDescription(from: testsToRun)) provided, but only one 'Tests to Run' is supported."
    }
  }
}

public struct FBXCTestRunRequest {

  /// How the test bundle to run is named: by the identifier of a bundle already stored on the companion, or by a path to a bundle on the host.
  public enum BundleSource: Equatable {
    case identifier(String)
    case path(URL)
  }

  /// How the test bundle is hosted, and the applications each hosting arrangement requires.
  public enum Mode: Equatable {
    case logic
    case application(testHostAppBundleID: String)
    case ui(testHostAppBundleID: String, testTargetAppBundleID: String)
  }

  public let bundle: BundleSource
  public let mode: Mode
  public let environment: [String: String]
  public let arguments: [String]
  public let testsToRun: Set<String>?
  public let testsToSkip: Set<String>
  public let testTimeout: NSNumber?
  public let reportActivities: Bool
  public let reportAttachments: Bool
  public let coverageRequest: FBCodeCoverageRequest
  public let collectLogs: Bool
  public let waitForDebugger: Bool
  public let collectResultBundle: Bool

  public var testBundleID: String? {
    guard case let .identifier(identifier) = bundle else { return nil }
    return identifier
  }

  public var testPath: URL? {
    guard case let .path(path) = bundle else { return nil }
    return path
  }

  public var testHostAppBundleID: String? {
    switch mode {
    case .logic:
      return nil
    case let .application(testHostAppBundleID):
      return testHostAppBundleID
    case let .ui(testHostAppBundleID, _):
      return testHostAppBundleID
    }
  }

  public var testTargetAppBundleID: String? {
    guard case let .ui(_, testTargetAppBundleID) = mode else { return nil }
    return testTargetAppBundleID
  }

  var isLogicTest: Bool {
    mode == .logic
  }

  var isUITest: Bool {
    guard case .ui = mode else { return false }
    return true
  }

  private init(bundle: BundleSource, mode: Mode, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) {
    self.bundle = bundle
    self.mode = mode
    self.environment = environment
    self.arguments = arguments
    self.testsToRun = testsToRun
    self.testsToSkip = testsToSkip
    self.testTimeout = testTimeout
    self.reportActivities = reportActivities
    self.reportAttachments = reportAttachments
    self.coverageRequest = coverageRequest
    self.collectLogs = collectLogs
    self.waitForDebugger = waitForDebugger
    self.collectResultBundle = collectResultBundle
  }

  // MARK: - Initializers

  public static func logicTest(withTestBundleID testBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest(bundle: .identifier(testBundleID), mode: .logic, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  public static func logicTest(withTestPath testPath: URL, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest(bundle: .path(testPath), mode: .logic, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  public static func applicationTest(withTestBundleID testBundleID: String, testHostAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest(bundle: .identifier(testBundleID), mode: .application(testHostAppBundleID: testHostAppBundleID), environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  public static func applicationTest(withTestPath testPath: URL, testHostAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest(bundle: .path(testPath), mode: .application(testHostAppBundleID: testHostAppBundleID), environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  public static func uiTest(withTestBundleID testBundleID: String, testHostAppBundleID: String, testTargetAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest(bundle: .identifier(testBundleID), mode: .ui(testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: testTargetAppBundleID), environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: false, collectResultBundle: collectResultBundle)
  }

  public static func uiTest(withTestPath testPath: URL, testHostAppBundleID: String, testTargetAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest(bundle: .path(testPath), mode: .ui(testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: testTargetAppBundleID), environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: false, collectResultBundle: collectResultBundle)
  }

  // MARK: - Test Execution

  func start(withBundleStorageManager bundleStorage: FBXCTestBundleStorage, target: any FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) async throws -> FBIDBTestOperation {
    let descriptor = try await fetchAndSetupDescriptor(withBundleStorage: bundleStorage, target: target)
    var logDirectoryPath: String?
    if collectLogs {
      let directory = temporaryDirectory.ephemeralTemporaryDirectory()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      logDirectoryPath = directory.path
    }
    switch mode {
    case .logic:
      return try startLogicTest(with: descriptor, logDirectoryPath: logDirectoryPath, target: target, reporter: reporter, logger: logger, temporaryDirectory: temporaryDirectory)
    case .application, .ui:
      return try await startAppHostedTest(with: descriptor, logDirectoryPath: logDirectoryPath, target: target, reporter: reporter, logger: logger)
    }
  }

  private func fetchAndSetupDescriptor(withBundleStorage bundleStorage: FBXCTestBundleStorage, target: any FBiOSTarget) async throws -> FBXCTestDescriptor {
    let descriptor = try fetchDescriptor(withBundleStorage: bundleStorage)
    try await descriptor.setupAsync(with: self, target: target)
    return descriptor
  }

  private func fetchDescriptor(withBundleStorage bundleStorage: FBXCTestBundleStorage) throws -> FBXCTestDescriptor {
    switch bundle {
    case let .identifier(identifier):
      return try bundleStorage.testDescriptor(withID: identifier)
    case let .path(path):
      switch path.pathExtension {
      case "xctest":
        let testBundle = try FBBundleDescriptor.bundle(fromPath: path.path)
        return FBXCTestBootstrapDescriptor(url: path, name: testBundle.name, testBundle: testBundle)
      case "xctestrun":
        let descriptors = try bundleStorage.getXCTestRunDescriptors(from: path)
        if descriptors.count != 1 {
          throw FBXCTestRunRequestError.notExactlyOneTest(count: descriptors.count)
        }
        return descriptors[0]
      default:
        throw FBXCTestRunRequestError.testDescriptorNotFound
      }
    }
  }

  // MARK: - Logic Tests

  private func startLogicTest(with testDescriptor: FBXCTestDescriptor, logDirectoryPath: String?, target: any FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) throws -> FBIDBTestOperation {
    let workingDirectory = temporaryDirectory.ephemeralTemporaryDirectory()
    try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true, attributes: nil)

    var coverageConfig: FBCodeCoverageConfiguration?
    if coverageRequest.collect {
      let dir = temporaryDirectory.ephemeralTemporaryDirectory()
      let coverageDirName = "coverage_\(NSUUID().uuidString)"
      let coverageDirPath = (dir.path as NSString).appendingPathComponent(coverageDirName)
      try FileManager.default.createDirectory(atPath: coverageDirPath, withIntermediateDirectories: true, attributes: nil)
      coverageConfig = FBCodeCoverageConfiguration(directory: coverageDirPath, format: coverageRequest.format, enableContinuousCoverageCollection: coverageRequest.shouldEnableContinuousCoverageCollection)
    }

    let testsToSkipArray = testsToSkip.sorted()
    if !testsToSkipArray.isEmpty {
      throw FBXCTestRunRequestError.testsToSkipUnsupported(testsToSkip: testsToSkipArray)
    }
    let testsToRunArray = testsToRun?.sorted() ?? []
    if testsToRunArray.count > 1 {
      throw FBXCTestRunRequestError.multipleTestsToRun(testsToRun: testsToRunArray)
    }
    let testFilter = testsToRunArray.first

    let timeout = testTimeout.flatMap { $0.boolValue ? $0.doubleValue : nil } ?? FBLogicTestTimeout
    let configuration = FBLogicTestConfiguration(
      environment: environment,
      workingDirectory: workingDirectory.path,
      testBundlePath: testDescriptor.testBundle.path,
      waitForDebugger: waitForDebugger,
      timeout: timeout,
      testFilter: testFilter,
      mirroring: .fileLogs,
      coverageConfiguration: coverageConfig,
      binaryPath: testDescriptor.testBundle.binary?.path,
      logDirectoryPath: logDirectoryPath,
      architectures: testDescriptor.architectures
    )

    return try startLogicTestExecution(configuration, target: target, reporter: reporter, logger: logger)
  }

  private func startLogicTestExecution(_ configuration: FBLogicTestConfiguration, target: any FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger) throws -> FBIDBTestOperation {
    guard let target = target as? any LogicTestTarget else {
      throw FBXCTestRunRequestError.logicTestsUnsupported(targetDescription: String(describing: target))
    }
    let adapter = FBLogicReporterAdapter(reporter: reporter, logger: logger)
    let runner = FBLogicTestRunStrategy(
      target: target,
      configuration: configuration,
      reporter: adapter,
      logger: logger
    )
    let completed = runner.execute()
    if let error = completed.error {
      throw error
    }
    let reporterConfiguration = FBXCTestReporterConfiguration(
      resultBundlePath: nil,
      coverageConfiguration: configuration.coverageConfiguration,
      logDirectoryPath: configuration.logDirectoryPath,
      binariesPaths: [configuration.binaryPath].compactMap { $0 },
      reportAttachments: reportAttachments,
      reportResultBundle: collectResultBundle
    )
    return FBIDBTestOperation(
      configuration: .logic(configuration),
      reporterConfiguration: reporterConfiguration,
      reporter: reporter,
      logger: logger,
      completed: completed,
      queue: target.workQueue
    )
  }

  // MARK: - Application-Hosted Tests

  private func startAppHostedTest(with testDescriptor: FBXCTestDescriptor, logDirectoryPath: String?, target: any FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger) async throws -> FBIDBTestOperation {
    let appPair = try await testDescriptor.testAppPair(for: self, target: target)
    logger.log("Obtaining launch configuration for App Pair \(appPair) on descriptor \(testDescriptor)")
    let appHostedTestConfig = try await testDescriptor.testConfig(withRunRequest: self, testApps: appPair, logDirectoryPath: logDirectoryPath, logger: logger)
    logger.log("Obtained app-hosted test configuration \(appHostedTestConfig)")
    return try Self.startAppHostedTestExecution(appHostedTestConfig, reportAttachments: reportAttachments, target: target, reporter: reporter, logger: logger, reportResultBundle: collectResultBundle)
  }

  private static func startAppHostedTestExecution(_ configuration: FBIDBAppHostedTestConfiguration, reportAttachments: Bool, target: any FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, reportResultBundle: Bool) throws -> FBIDBTestOperation {
    guard let target = target as? any XCTestTarget else {
      throw FBXCTestRunRequestError.xctestUnsupported(targetDescription: String(describing: target))
    }
    let testLaunchConfiguration = configuration.testLaunchConfiguration
    let coverageConfiguration = configuration.coverageConfiguration

    var binariesPaths: [String] = []
    if let binaryPath = testLaunchConfiguration.testBundle.binary?.path {
      binariesPaths.append(binaryPath)
    }
    if let binaryPath = testLaunchConfiguration.testHostBundle?.binary?.path {
      binariesPaths.append(binaryPath)
    }
    if let binaryPath = testLaunchConfiguration.targetApplicationBundle?.binary?.path {
      binariesPaths.append(binaryPath)
    }

    let testCompleted: FBFuture<NSNull> = fbFutureFromAsync {
      try await target.xctest.runTest(launchConfiguration: testLaunchConfiguration, reporter: reporter, logger: logger)
      return NSNull()
    }
    let reporterConfiguration = FBXCTestReporterConfiguration(
      resultBundlePath: testLaunchConfiguration.resultBundlePath,
      coverageConfiguration: coverageConfiguration,
      logDirectoryPath: testLaunchConfiguration.logDirectoryPath,
      binariesPaths: binariesPaths,
      reportAttachments: reportAttachments,
      reportResultBundle: reportResultBundle
    )
    return FBIDBTestOperation(
      configuration: .appHosted(testLaunchConfiguration),
      reporterConfiguration: reporterConfiguration,
      reporter: reporter,
      logger: logger,
      completed: testCompleted,
      queue: target.workQueue
    )
  }
}

// MARK: - CustomStringConvertible

extension FBXCTestRunRequest: CustomStringConvertible {
  public var description: String {
    switch mode {
    case .logic:
      return "logic test of \(bundle)"
    case let .application(testHostAppBundleID):
      return "application test of \(bundle) hosted by \(testHostAppBundleID)"
    case let .ui(testHostAppBundleID, testTargetAppBundleID):
      return "ui test of \(bundle) hosted by \(testHostAppBundleID) targeting \(testTargetAppBundleID)"
    }
  }
}

extension FBXCTestRunRequest.BundleSource: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .identifier(identifier):
      return "bundle id \(identifier)"
    case let .path(path):
      return "bundle at \(path.path)"
    }
  }
}
