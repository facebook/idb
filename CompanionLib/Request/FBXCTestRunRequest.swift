/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

private let FBLogicTestTimeout: TimeInterval = 60 * 60 // Aprox. an hour.

// MARK: - FBXCTestRunRequest

@objc public class FBXCTestRunRequest: NSObject {
  @objc public let testBundleID: String?
  @objc public let testPath: URL?
  @objc public let testHostAppBundleID: String?
  @objc public let testTargetAppBundleID: String?
  @objc public let environment: [String: String]
  @objc public let arguments: [String]
  @objc public let testsToRun: Set<String>?
  @objc public let testsToSkip: Set<String>
  @objc public let testTimeout: NSNumber?
  @objc public let reportActivities: Bool
  @objc public let reportAttachments: Bool
  @objc public let coverageRequest: FBCodeCoverageRequest
  @objc public let collectLogs: Bool
  @objc public let waitForDebugger: Bool
  @objc public let collectResultBundle: Bool

  @objc public var isLogicTest: Bool { false }
  @objc public var isUITest: Bool { false }

  // MARK: - Initializers

  @objc public static func logicTest(withTestBundleID testBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    return FBXCTestRunRequest_LogicTest(testBundleID: testBundleID, testHostAppBundleID: nil, testTargetAppBundleID: nil, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  @objc public static func logicTest(withTestPath testPath: URL, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    return FBXCTestRunRequest_LogicTest(testPath: testPath, testHostAppBundleID: nil, testTargetAppBundleID: nil, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  @objc public static func applicationTest(withTestBundleID testBundleID: String, testHostAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    return FBXCTestRunRequest_AppTest(testBundleID: testBundleID, testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: nil, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  @objc public static func applicationTest(withTestPath testPath: URL, testHostAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, waitForDebugger: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    return FBXCTestRunRequest_AppTest(testPath: testPath, testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: nil, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: waitForDebugger, collectResultBundle: collectResultBundle)
  }

  @objc public static func uiTest(withTestBundleID testBundleID: String, testHostAppBundleID: String, testTargetAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    return FBXCTestRunRequest_UITest(testBundleID: testBundleID, testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: testTargetAppBundleID, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: false, collectResultBundle: collectResultBundle)
  }

  @objc public static func uiTest(withTestPath testPath: URL, testHostAppBundleID: String, testTargetAppBundleID: String, environment: [String: String], arguments: [String], testsToRun: Set<String>?, testsToSkip: Set<String>, testTimeout: NSNumber?, reportActivities: Bool, reportAttachments: Bool, coverageRequest: FBCodeCoverageRequest, collectLogs: Bool, collectResultBundle: Bool) -> FBXCTestRunRequest {
    return FBXCTestRunRequest_UITest(testPath: testPath, testHostAppBundleID: testHostAppBundleID, testTargetAppBundleID: testTargetAppBundleID, environment: environment, arguments: arguments, testsToRun: testsToRun, testsToSkip: testsToSkip, testTimeout: testTimeout, reportActivities: reportActivities, reportAttachments: reportAttachments, coverageRequest: coverageRequest, collectLogs: collectLogs, waitForDebugger: false, collectResultBundle: collectResultBundle)
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

  @objc public func start(withBundleStorageManager bundleStorage: FBXCTestBundleStorage, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) -> FBFuture<FBIDBTestOperation> {
    return
      (fetchAndSetupDescriptor(withBundleStorage: bundleStorage, target: target)
      .onQueue(
        target.workQueue,
        fmap: { descriptor in
          let descriptorObj = descriptor as! FBXCTestDescriptor
          var logDirectoryPath: String?
          if self.collectLogs {
            let directory = temporaryDirectory.ephemeralTemporaryDirectory()
            do {
              try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
              return FBFuture(error: error as NSError)
            }
            logDirectoryPath = directory.path
          }
          return self.startWithTestDescriptor(descriptorObj, logDirectoryPath: logDirectoryPath, reportActivities: self.reportActivities, target: target, reporter: reporter, logger: logger, temporaryDirectory: temporaryDirectory) as! FBFuture<AnyObject>
        }) as AnyObject) as! FBFuture<FBIDBTestOperation>
  }

  func startWithTestDescriptor(_ testDescriptor: FBXCTestDescriptor, logDirectoryPath: String?, reportActivities: Bool, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) -> FBFuture<FBIDBTestOperation> {
    return FBIDBError.describe("\(type(of: self)) not implemented in abstract base class").failFuture() as! FBFuture<FBIDBTestOperation>
  }

  private func fetchAndSetupDescriptor(withBundleStorage bundleStorage: FBXCTestBundleStorage, target: FBiOSTarget) -> FBFuture<AnyObject> {
    var testDescriptor: FBXCTestDescriptor?

    if let filePath = self.testPath {
      if filePath.pathExtension == "xctest" {
        do {
          let bundle = try FBBundleDescriptor.bundle(fromPath: filePath.path)
          testDescriptor = FBXCTestBootstrapDescriptor(url: filePath, name: bundle.name, testBundle: bundle)
        } catch {
          return FBFuture(error: error as NSError)
        }
      }
      if filePath.pathExtension == "xctestrun" {
        do {
          let descriptors = try bundleStorage.getXCTestRunDescriptors(from: filePath)
          if descriptors.count != 1 {
            return FBIDBError.describe("Expected exactly one test in the xctestrun file, got: \(descriptors.count)").failFuture()
          }
          testDescriptor = descriptors[0]
        } catch {
          return FBFuture(error: error as NSError)
        }
      }
    } else {
      guard let bundleID = testBundleID else {
        return FBIDBError.describe("No test bundle ID provided").failFuture()
      }
      do {
        testDescriptor = try bundleStorage.testDescriptor(withID: bundleID)
      } catch {
        return FBFuture(error: error as NSError)
      }
    }

    guard let descriptor = testDescriptor else {
      return FBIDBError.describe("Could not find test descriptor").failFuture()
    }

    return descriptor.setup(with: self, target: target).mapReplace(descriptor as AnyObject) as FBFuture
  }
}

// MARK: - Private Subclasses

private class FBXCTestRunRequest_LogicTest: FBXCTestRunRequest {
  override var isLogicTest: Bool { true }
  override var isUITest: Bool { false }

  override func startWithTestDescriptor(_ testDescriptor: FBXCTestDescriptor, logDirectoryPath: String?, reportActivities: Bool, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) -> FBFuture<FBIDBTestOperation> {
    let workingDirectory = temporaryDirectory.ephemeralTemporaryDirectory()
    do {
      try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      return FBFuture(error: error as NSError)
    }

    var coverageConfig: FBCodeCoverageConfiguration?
    if coverageRequest.collect {
      let dir = temporaryDirectory.ephemeralTemporaryDirectory()
      let coverageDirName = "coverage_\(NSUUID().uuidString)"
      let coverageDirPath = (dir.path as NSString).appendingPathComponent(coverageDirName)
      do {
        try FileManager.default.createDirectory(atPath: coverageDirPath, withIntermediateDirectories: true, attributes: nil)
      } catch {
        return FBFuture(error: error as NSError)
      }
      coverageConfig = FBCodeCoverageConfiguration(directory: coverageDirPath, format: coverageRequest.format, enableContinuousCoverageCollection: coverageRequest.shouldEnableContinuousCoverageCollection)
    }

    let testsToSkipArray = testsToSkip.sorted()
    if !testsToSkipArray.isEmpty {
      return FBXCTestError.describe("'Tests to Skip' \(FBCollectionInformation.oneLineDescription(from: testsToSkipArray)) provided, but Logic Tests to not support this.").failFuture() as! FBFuture<FBIDBTestOperation>
    }
    let testsToRunArray = testsToRun?.sorted() ?? []
    if testsToRunArray.count > 1 {
      return FBXCTestError.describe("More than one 'Tests to Run' \(FBCollectionInformation.oneLineDescription(from: testsToRunArray)) provided, but only one 'Tests to Run' is supported.").failFuture() as! FBFuture<FBIDBTestOperation>
    }
    let testFilter = testsToRunArray.first

    let timeout = testTimeout?.boolValue == true ? testTimeout!.doubleValue : FBLogicTestTimeout
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

    return startTestExecution(configuration, target: target, reporter: reporter, logger: logger)
  }

  private func startTestExecution(_ configuration: FBLogicTestConfiguration, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger) -> FBFuture<FBIDBTestOperation> {
    let adapter = FBLogicReporterAdapter(reporter: reporter, logger: logger)
    let runner = FBLogicTestRunStrategy(
      target: target as! (FBiOSTarget & FBProcessSpawnCommands & FBXCTestExtendedCommands),
      configuration: configuration,
      reporter: adapter,
      logger: logger
    )
    let completed = runner.execute()
    if let error = completed.error {
      return FBFuture(error: error)
    }
    let reporterConfiguration = FBXCTestReporterConfiguration(
      resultBundlePath: nil,
      coverageConfiguration: configuration.coverageConfiguration,
      logDirectoryPath: configuration.logDirectoryPath,
      binariesPaths: [configuration.binaryPath].compactMap { $0 },
      reportAttachments: reportAttachments,
      reportResultBundle: collectResultBundle
    )
    let operation = FBIDBTestOperation(
      configuration: configuration,
      reporterConfiguration: reporterConfiguration,
      reporter: reporter,
      logger: logger,
      completed: completed,
      queue: target.workQueue
    )
    return FBFuture(result: operation)
  }
}

private class FBXCTestRunRequest_AppTest: FBXCTestRunRequest {
  override var isLogicTest: Bool { false }
  override var isUITest: Bool { false }

  override func startWithTestDescriptor(_ testDescriptor: FBXCTestDescriptor, logDirectoryPath: String?, reportActivities: Bool, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, temporaryDirectory: FBTemporaryDirectory) -> FBFuture<FBIDBTestOperation> {
    return
      (testDescriptor.testAppPair(for: self, target: target)
      .onQueue(
        target.workQueue,
        fmap: { pair in
          let appPair = pair as FBTestApplicationsPair
          logger.log("Obtaining launch configuration for App Pair \(appPair) on descriptor \(testDescriptor)")
          return testDescriptor.testConfig(withRunRequest: self, testApps: appPair, logDirectoryPath: logDirectoryPath, logger: logger, queue: target.workQueue) as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        target.workQueue,
        fmap: { config in
          let appHostedTestConfig = config as! FBIDBAppHostedTestConfiguration
          logger.log("Obtained app-hosted test configuration \(appHostedTestConfig)")
          return FBXCTestRunRequest_AppTest.startTestExecution(appHostedTestConfig, reportAttachments: self.reportAttachments, target: target, reporter: reporter, logger: logger, reportResultBundle: self.collectResultBundle) as! FBFuture<AnyObject>
        }) as AnyObject) as! FBFuture<FBIDBTestOperation>
  }

  static func startTestExecution(_ configuration: FBIDBAppHostedTestConfiguration, reportAttachments: Bool, target: FBiOSTarget, reporter: FBXCTestReporter, logger: FBControlCoreLogger, reportResultBundle: Bool) -> FBFuture<FBIDBTestOperation> {
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

    let testCompleted = target.runTest(with: testLaunchConfiguration, reporter: reporter, logger: logger)
    let reporterConfiguration = FBXCTestReporterConfiguration(
      resultBundlePath: testLaunchConfiguration.resultBundlePath,
      coverageConfiguration: coverageConfiguration,
      logDirectoryPath: testLaunchConfiguration.logDirectoryPath,
      binariesPaths: binariesPaths,
      reportAttachments: reportAttachments,
      reportResultBundle: reportResultBundle
    )
    let operation = FBIDBTestOperation(
      configuration: testLaunchConfiguration,
      reporterConfiguration: reporterConfiguration,
      reporter: reporter,
      logger: logger,
      completed: testCompleted,
      queue: target.workQueue
    )
    return FBFuture(result: operation)
  }
}

private class FBXCTestRunRequest_UITest: FBXCTestRunRequest_AppTest {
  override var isLogicTest: Bool { false }
  override var isUITest: Bool { true }
}
