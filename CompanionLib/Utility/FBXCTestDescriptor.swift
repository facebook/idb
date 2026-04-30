/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

@objc public protocol FBXCTestDescriptor: NSObjectProtocol {
  var url: URL { get }
  var name: String { get }
  var testBundleID: String { get }
  var architectures: Set<String> { get }
  var testBundle: FBBundleDescriptor { get }
  func setup(with request: FBXCTestRunRequest, target: FBiOSTarget) -> FBFuture<NSNull>
  func testConfig(withRunRequest request: FBXCTestRunRequest, testApps: FBTestApplicationsPair, logDirectoryPath: String?, logger: FBControlCoreLogger, queue: DispatchQueue) -> FBFuture<FBIDBAppHostedTestConfiguration>
  func testAppPair(for request: FBXCTestRunRequest, target: FBiOSTarget) -> FBFuture<FBTestApplicationsPair>
}

public extension FBXCTestDescriptor {
  /// Async wrapper for `setup(with:target:)`.
  func setupAsync(with request: FBXCTestRunRequest, target: FBiOSTarget) async throws {
    try await bridgeFBFutureVoid(self.setup(with: request, target: target))
  }

  /// Async wrapper for `testAppPair(for:target:)`.
  func testAppPairAsync(for request: FBXCTestRunRequest, target: FBiOSTarget) async throws -> FBTestApplicationsPair {
    try await bridgeFBFuture(self.testAppPair(for: request, target: target))
  }

  /// Async wrapper for `testConfig(withRunRequest:testApps:logDirectoryPath:logger:queue:)`.
  func testConfigAsync(withRunRequest request: FBXCTestRunRequest, testApps: FBTestApplicationsPair, logDirectoryPath: String?, logger: FBControlCoreLogger, queue: DispatchQueue) async throws -> FBIDBAppHostedTestConfiguration {
    try await bridgeFBFuture(self.testConfig(withRunRequest: request, testApps: testApps, logDirectoryPath: logDirectoryPath, logger: logger, queue: queue))
  }
}

// MARK: - FBXCTestBootstrapDescriptor

@objc public final class FBXCTestBootstrapDescriptor: NSObject, FBXCTestDescriptor {

  @objc public let url: URL
  @objc public let name: String
  @objc public let testBundle: FBBundleDescriptor
  private var targetAuxillaryDirectory: String = ""

  @objc public var testBundleID: String {
    testBundle.identifier
  }

  @objc public var architectures: Set<String> {
    testBundle.binary!.architectures as! Set<String>
  }

  @objc public init(url: URL, name: String, testBundle: FBBundleDescriptor) {
    self.url = url
    self.name = name
    self.testBundle = testBundle
    super.init()
  }

  public override var description: String {
    "xctestbootstrap descriptor for \(url) \(name) \(testBundle)"
  }

  // MARK: - Private

  private static func killAllRunningApplications(_ target: FBiOSTarget) -> FBFuture<NSNull> {
    return target.runningApplications()
      .onQueue(
        target.workQueue,
        fmap: { runningApplications in
          let runningApps = runningApplications as! [String: FBProcessInfo]
          let killFutures: [FBFuture<AnyObject>] = runningApps.keys.map { bundleID in
            target.killApplication(withBundleID: bundleID) as! FBFuture<AnyObject>
          }
          if killFutures.isEmpty {
            return FBFuture(result: NSNull() as AnyObject)
          }
          return unsafeBitCast(FBFuture<AnyObject>.combine(killFutures), to: FBFuture<AnyObject>.self)
        }
      )
      .mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  // MARK: - FBXCTestDescriptor

  @objc public func setup(with request: FBXCTestRunRequest, target: FBiOSTarget) -> FBFuture<NSNull> {
    targetAuxillaryDirectory = target.auxillaryDirectory
    if request.isLogicTest {
      return FBFuture<NSNull>.empty()
    }
    return FBXCTestBootstrapDescriptor.killAllRunningApplications(target).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  @objc public func testAppPair(for request: FBXCTestRunRequest, target: FBiOSTarget) -> FBFuture<FBTestApplicationsPair> {
    if request.isLogicTest {
      return FBFuture(result: FBTestApplicationsPair(applicationUnderTest: nil, testHostApp: nil))
    }
    if request.isUITest {
      guard let testTargetAppBundleID = request.testTargetAppBundleID else {
        return FBIDBError.describe("Request for UI Test, but no app_bundle_id provided").failFuture() as! FBFuture<FBTestApplicationsPair>
      }
      let testHostBundleID = request.testHostAppBundleID ?? "com.apple.Preferences"
      return FBFuture<AnyObject>.combine([
        target.installedApplication(withBundleID: testTargetAppBundleID) as! FBFuture<AnyObject>,
        target.installedApplication(withBundleID: testHostBundleID) as! FBFuture<AnyObject>,
      ])
      .onQueue(
        target.asyncQueue,
        map: { results -> AnyObject in
          let applications = results as! [FBInstalledApplication]
          return FBTestApplicationsPair(applicationUnderTest: applications[0], testHostApp: applications[1])
        }) as! FBFuture<FBTestApplicationsPair>
    }
    // App Test
    guard let bundleID = request.testHostAppBundleID else {
      return FBIDBError.describe("Request for Application Test, but no app_bundle_id or test_host_app_bundle_id provided").failFuture() as! FBFuture<FBTestApplicationsPair>
    }
    return target.installedApplication(withBundleID: bundleID)
      .onQueue(
        target.asyncQueue,
        map: { application -> AnyObject in
          return FBTestApplicationsPair(applicationUnderTest: nil, testHostApp: application as FBInstalledApplication)
        }) as! FBFuture<FBTestApplicationsPair>
  }

  @objc public func testConfig(withRunRequest request: FBXCTestRunRequest, testApps: FBTestApplicationsPair, logDirectoryPath: String?, logger: FBControlCoreLogger, queue: DispatchQueue) -> FBFuture<FBIDBAppHostedTestConfiguration> {
    let appLaunchConfigFuture = buildAppLaunchConfig(
      bundleID: testApps.testHostApp!.bundle.identifier,
      environment: request.environment,
      arguments: request.arguments,
      logger: logger,
      processLogDirectory: logDirectoryPath,
      waitForDebugger: request.waitForDebugger,
      queue: queue
    )
    var coverageConfig: FBCodeCoverageConfiguration?
    if request.coverageRequest.collect {
      let coverageDirName = "coverage_\(UUID().uuidString)"
      let coverageDirPath = (targetAuxillaryDirectory as NSString).appendingPathComponent(coverageDirName)
      do {
        try FileManager.default.createDirectory(atPath: coverageDirPath, withIntermediateDirectories: true, attributes: nil)
      } catch {
        return FBFuture(error: error as NSError)
      }
      coverageConfig = FBCodeCoverageConfiguration(
        directory: coverageDirPath,
        format: request.coverageRequest.format,
        enableContinuousCoverageCollection: request.coverageRequest.shouldEnableContinuousCoverageCollection
      )
    }

    return appLaunchConfigFuture.onQueue(
      queue,
      map: { result -> AnyObject in
        let applicationLaunchConfiguration = result as! FBApplicationLaunchConfiguration
        let testLaunchConfig = FBTestLaunchConfiguration(
          testBundle: self.testBundle,
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
        return FBIDBAppHostedTestConfiguration(testLaunchConfiguration: testLaunchConfig, coverageConfiguration: coverageConfig)
      }) as! FBFuture<FBIDBAppHostedTestConfiguration>
  }
}

// MARK: - FBXCodebuildTestRunDescriptor

@objc public final class FBXCodebuildTestRunDescriptor: NSObject, FBXCTestDescriptor {

  @objc public let url: URL
  @objc public let name: String
  @objc public let testBundle: FBBundleDescriptor
  @objc public let testHostBundle: FBBundleDescriptor
  private var targetAuxillaryDirectory: String = ""

  @objc public var testBundleID: String {
    testBundle.identifier
  }

  @objc public var architectures: Set<String> {
    testHostBundle.binary!.architectures as! Set<String>
  }

  @objc public init(url: URL, name: String, testBundle: FBBundleDescriptor, testHostBundle: FBBundleDescriptor) {
    self.url = url
    self.name = name
    self.testBundle = testBundle
    self.testHostBundle = testHostBundle
    super.init()
  }

  public override var description: String {
    "xcodebuild descriptor for \(url) \(name) \(testBundle) \(testHostBundle)"
  }

  // MARK: - FBXCTestDescriptor

  @objc public func setup(with request: FBXCTestRunRequest, target: FBiOSTarget) -> FBFuture<NSNull> {
    targetAuxillaryDirectory = target.auxillaryDirectory
    return FBFuture<NSNull>.empty()
  }

  @objc public func testAppPair(for request: FBXCTestRunRequest, target: FBiOSTarget) -> FBFuture<FBTestApplicationsPair> {
    FBFuture(result: FBTestApplicationsPair(applicationUnderTest: nil, testHostApp: nil))
  }

  @objc public func testConfig(withRunRequest request: FBXCTestRunRequest, testApps: FBTestApplicationsPair, logDirectoryPath: String?, logger: FBControlCoreLogger, queue: DispatchQueue) -> FBFuture<FBIDBAppHostedTestConfiguration> {
    let resultBundleName = "resultbundle_\(UUID().uuidString)"
    let resultBundlePath = (targetAuxillaryDirectory as NSString).appendingPathComponent(resultBundleName)

    let properties: [String: Any]
    do {
      properties = try FBXCTestRunFileReader.readContents(of: url, expandPlaceholderWithPath: targetAuxillaryDirectory)
    } catch {
      return FBFuture(error: error as NSError)
    }

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

    let testLaunchConfiguration = FBTestLaunchConfiguration(
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

    return FBFuture(result: FBIDBAppHostedTestConfiguration(testLaunchConfiguration: testLaunchConfiguration, coverageConfiguration: nil))
  }
}

// MARK: - Private Helper

private func buildAppLaunchConfig(bundleID: String, environment: [String: String], arguments: [String], logger: FBControlCoreLogger, processLogDirectory: String?, waitForDebugger: Bool, queue: DispatchQueue) -> FBFuture<AnyObject> {
  let stdOutConsumer = FBLoggingDataConsumer(logger: logger)
  let stdErrConsumer = FBLoggingDataConsumer(logger: logger)

  var stdOutFuture: FBFuture<AnyObject> = FBFuture(result: stdOutConsumer as AnyObject)
  var stdErrFuture: FBFuture<AnyObject> = FBFuture(result: stdErrConsumer as AnyObject)

  if let processLogDirectory {
    let mirrorLogger = FBXCTestLogger.defaultLogger(inDirectory: processLogDirectory)
    stdOutFuture = mirrorLogger.logConsumption(of: stdOutConsumer, toFileNamed: "test_process_stdout.out", logger: logger)
    stdErrFuture = mirrorLogger.logConsumption(of: stdErrConsumer, toFileNamed: "test_process_stderr.err", logger: logger)
  }

  let combined = FBFuture<AnyObject>.combine([stdOutFuture, stdErrFuture])
  return combined.onQueue(
    queue,
    map: { results -> AnyObject in
      let resultsArray = results as [AnyObject]
      let stdOutResult = resultsArray[0]
      let stdErrResult = resultsArray[1]
      let outputCls = unsafeBitCast(FBProcessOutput<AnyObject>.self, to: NSObject.Type.self)
      let sel = NSSelectorFromString("outputForDataConsumer:")
      let stdOut = outputCls.perform(sel, with: stdOutResult)!.takeUnretainedValue() as! FBProcessOutput<AnyObject>
      let stdErr = outputCls.perform(sel, with: stdErrResult)!.takeUnretainedValue() as! FBProcessOutput<AnyObject>
      let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: stdOut, stdErr: stdErr)
      return FBApplicationLaunchConfiguration(
        bundleID: bundleID,
        bundleName: nil,
        arguments: arguments,
        environment: environment,
        waitForDebugger: waitForDebugger,
        io: io,
        launchMode: .relaunchIfRunning
      )
    })
}
