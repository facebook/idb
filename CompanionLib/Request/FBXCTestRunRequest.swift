/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

private let FBLogicTestTimeout: TimeInterval = 60 * 60 // Approx. an hour.

// MARK: - FBXCTestRunRequest

/// The ways a test-run request can fail before execution, as data rather than assembled strings.
public enum FBXCTestRunRequestError: Error {
  case abstractBaseClass(typeName: String)
  case notExactlyOneTest(count: Int)
  case noTestBundleID
  case testDescriptorNotFound
  case logicTestsUnsupported(targetDescription: String)
  case testsToSkipUnsupported(testsToSkip: [String])
  case multipleTestsToRun(testsToRun: [String])
  case xctestCommandsUnsupported(targetDescription: String)
}

extension FBXCTestRunRequestError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .abstractBaseClass(typeName):
      return "\(typeName) not implemented in abstract base class"
    case let .notExactlyOneTest(count):
      return "Expected exactly one test in the xctestrun file, got: \(count)"
    case .noTestBundleID:
      return "No test bundle ID provided"
    case .testDescriptorNotFound:
      return "Could not find test descriptor"
    case let .logicTestsUnsupported(targetDescription):
      return "Target \(targetDescription) does not support process spawning and extended xctest commands, cannot run logic tests"
    case let .testsToSkipUnsupported(testsToSkip):
      return "'Tests to Skip' \(FBCollectionInformation.oneLineDescription(from: testsToSkip)) provided, but Logic Tests do not support this."
    case let .multipleTestsToRun(testsToRun):
      return "More than one 'Tests to Run' \(FBCollectionInformation.oneLineDescription(from: testsToRun)) provided, but only one 'Tests to Run' is supported."
    case let .xctestCommandsUnsupported(targetDescription):
      return "\(targetDescription) does not support XCTestCommands"
    }
  }
}

public class FBXCTestRunRequest: NSObject {
  public let testBundleID: String?
  public let testPath: URL?
  public let testHostAppBundleID: String?
  public let testTargetAppBundleID: String?
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

  var isLogicTest: Bool { false }
  var isUITest: Bool { false }

  // MARK: - Initializers

  public static func logicTest(withTestBundleID testBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest_LogicTest(testBundleID: testBundleID, testHostAppBundleID: nil, testTargetAppBundleID: nil, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  public static func logicTest(withTestPath testPath: URL, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest_LogicTest(testPath: testPath, testHostAppBundleID: nil, testTargetAppBundleID: nil, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  public static func applicationTest(withTestBundleID testBundleID: String, testHostAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest_AppTest(testBundleID: testBundleID, testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: nil, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  public static func applicationTest(withTestPath testPath: URL, testHostAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest_AppTest(testPath: testPath, testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: nil, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  public static func uiTest(withTestBundleID testBundleID: String, testHostAppBundleID: String, testTargetAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest_UITest(testBundleID: testBundleID, testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: testTargetAppBundleID, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: false, collectResultBundle: collectResultBundle)
  }

  public static func uiTest(withTestPath testPath: URL, testHostAppBundleID: String, testTargetAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    FBXCTestRunRequest_UITest(testPath: testPath, testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: testTargetAppBundleID, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: false, collectResultBundle: collectResultBundle)
  }

  init(testBundleID: String, testHostAppBundleID: String?, testTargetAppBundleID: String?, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) {
    self.testBundleID = testBundleID
    self.testPath = nil
    self.testHostAppBundleID = testHostAppBundleID
    self.testTargetAppBundleID = testTargetAppBundleID
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
    super.init()
  }

  init(testPath: URL, testHostAppBundleID: String?, testTargetAppBundleID: String?, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) {
    self.testBundleID = nil
    self.testPath = testPath
    self.testHostAppBundleID = testHostAppBundleID
    self.testTargetAppBundleID = testTargetAppBundleID
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
    super.init()
  }

  // MARK: - Public Methods

  public func start(withBundleStorageManager bundleStorage: FBXCTestBundleStorage, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) -> FBFuture<FBIDBTestOperation> {
    fbFutureFromAsync { [self] in
      try await startAsync(withBundleStorageManager: bundleStorage, target: target, reporter: reporter, logger: logger, temporaryDirectory: temporaryDirectory)
    }
  }

  func startAsync(withBundleStorageManager bundleStorage: FBXCTestBundleStorage, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) async throws -> FBIDBTestOperation {
    let descriptor = try await fetchAndSetupDescriptorAsync(withBundleStorage: bundleStorage, target: target)
    var logDirectoryPath: String?
    if collectLogs {
      let directory = temporaryDirectory.ephemeralTemporaryDirectory()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      logDirectoryPath = directory.path
    }
    return try await startWithTestDescriptorAsync(descriptor, logDirectoryPath: logDirectoryPath, reportActivities: reportActivities, target: target, reporter: reporter, logger: logger, temporaryDirectory: temporaryDirectory)
  }

  func startWithTestDescriptorAsync(_ testDescriptor: FBXCTestDescriptor, logDirectoryPath: String?, reportActivities: Bool, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) async throws -> FBIDBTestOperation {
    throw FBXCTestRunRequestError.abstractBaseClass(typeName: String(describing: type(of: self)))
  }

  private func fetchAndSetupDescriptorAsync(withBundleStorage bundleStorage: FBXCTestBundleStorage, target: FBiOSTarget) async throws -> FBXCTestDescriptor {
    var testDescriptor: FBXCTestDescriptor?

    if let filePath = self.testPath {
      if filePath.pathExtension == "xctest" {
        let bundle = try FBBundleDescriptor.bundle(fromPath: filePath.path)
        testDescriptor = FBXCTestBootstrapDescriptor(url: filePath, name: bundle.name, testBundle: bundle)
      }
      if filePath.pathExtension == "xctestrun" {
        let descriptors = try bundleStorage.getXCTestRunDescriptors(from: filePath)
        if descriptors.count != 1 {
          throw FBXCTestRunRequestError.notExactlyOneTest(count: descriptors.count)
        }
        testDescriptor = descriptors[0]
      }
    } else {
      guard let bundleID = testBundleID else {
        throw FBXCTestRunRequestError.noTestBundleID
      }
      testDescriptor = try bundleStorage.testDescriptor(withID: bundleID)
    }

    guard let descriptor = testDescriptor else {
      throw FBXCTestRunRequestError.testDescriptorNotFound
    }

    try await descriptor.setupAsync(with: self, target: target)
    return descriptor
  }
}

// MARK: - Private Subclasses

private class FBXCTestRunRequest_LogicTest: FBXCTestRunRequest {
  override var isLogicTest: Bool { true }
  override var isUITest: Bool { false }

  override func startWithTestDescriptorAsync(_ testDescriptor: FBXCTestDescriptor, logDirectoryPath: String?, reportActivities: Bool, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) async throws -> FBIDBTestOperation {
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

    return try startTestExecution(configuration, target: target, reporter: reporter, logger: logger)
  }

  private func startTestExecution(_ configuration: FBLogicTestConfiguration, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger) throws -> FBIDBTestOperation {
    guard let target = target as? (FBiOSTarget & ProcessSpawnCommands & XCTestExtendedCommands) else {
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
}

private class FBXCTestRunRequest_AppTest: FBXCTestRunRequest {
  override var isLogicTest: Bool { false }
  override var isUITest: Bool { false }

  override func startWithTestDescriptorAsync(_ testDescriptor: FBXCTestDescriptor, logDirectoryPath: String?, reportActivities: Bool, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) async throws -> FBIDBTestOperation {
    let appPair = try await testDescriptor.testAppPairAsync(for: self, target: target)
    logger.log("Obtaining launch configuration for App Pair \(appPair) on descriptor \(testDescriptor)")
    let appHostedTestConfig = try await testDescriptor.testConfigAsync(withRunRequest: self, testApps: appPair, logDirectoryPath: logDirectoryPath, logger: logger, queue: target.workQueue)
    logger.log("Obtained app-hosted test configuration \(appHostedTestConfig)")
    return FBXCTestRunRequest_AppTest.startTestExecution(appHostedTestConfig, reportAttachments: reportAttachments, target: target, reporter: reporter, logger: logger, reportResultBundle: collectResultBundle)
  }

  static func startTestExecution(_ configuration: FBIDBAppHostedTestConfiguration, reportAttachments: Bool, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, reportResultBundle: Bool) -> FBIDBTestOperation {
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
      guard let asyncTarget = target as? any XCTestCommands else {
        throw FBXCTestRunRequestError.xctestCommandsUnsupported(targetDescription: String(describing: target))
      }
      try await asyncTarget.runTest(launchConfiguration: testLaunchConfiguration, reporter: reporter, logger: logger)
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

private class FBXCTestRunRequest_UITest: FBXCTestRunRequest_AppTest {
  override var isLogicTest: Bool { false }
  override var isUITest: Bool { true }
}
