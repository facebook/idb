/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let XcodebuildEnvironmentTargetUDID = "XCTESTBOOTSTRAP_TARGET_UDID"
private let XcodebuildEnvironmentDeviceSetPath = "SIM_DEVICE_SET_PATH"
private let XcodebuildEnvironmentInsertDylib = "DYLD_INSERT_LIBRARIES"
private let XcodebuildDestinationTimeoutSecs = "180"

@objc public final class FBXcodeBuildOperation: NSObject {

  // MARK: Initializers

  @objc public static func operation(withUDID udid: String, configuration: FBTestLaunchConfiguration, xcodeBuildPath: String, testRunFilePath: String, simDeviceSet simDeviceSetPath: String?, macOSTestShimPath: String?, queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    var arguments = [
      "test-without-building",
      "-xctestrun", testRunFilePath,
      "-destination", "id=\(udid)",
      "-destination-timeout", XcodebuildDestinationTimeoutSecs,
    ]

    if let resultBundlePath = configuration.resultBundlePath {
      arguments.append(contentsOf: ["-resultBundlePath", resultBundlePath])
    }

    for test in configuration.testsToRun ?? [] {
      arguments.append("-only-testing:\(test)")
    }

    for test in configuration.testsToSkip ?? [] {
      arguments.append("-skip-testing:\(test)")
    }

    var environment = ProcessInfo.processInfo.environment
    environment[XcodebuildEnvironmentTargetUDID] = udid

    if let simDeviceSetPath {
      guard let macOSTestShimPath else {
        return unsafeBitCast(
          XCTestBootstrapError.describe("Failed to locate the shim file for xcodebuild method swizzling").failFuture(),
          to: FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>.self
        )
      }
      environment[XcodebuildEnvironmentDeviceSetPath] = simDeviceSetPath
      if let existingDylib = environment[XcodebuildEnvironmentInsertDylib] {
        environment[XcodebuildEnvironmentInsertDylib] = "\(existingDylib):\(macOSTestShimPath)"
      } else {
        environment[XcodebuildEnvironmentInsertDylib] = macOSTestShimPath
      }
    }

    logger?.log("Starting test with xcodebuild | Arguments: \(arguments.joined(separator: " ")) | Environments: \(environment)")
    let base = FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath(xcodeBuildPath, arguments: arguments)
      .withEnvironment(environment)
      .withTaskLifecycleLogging(to: logger)
    let startFuture: FBFuture<AnyObject>
    if let logger {
      let configured = base.withStdOut(toLoggerAndErrorMessage: logger).withStdErr(toLoggerAndErrorMessage: logger)
      startFuture = unsafeBitCast(configured.start(), to: FBFuture<AnyObject>.self)
    } else {
      startFuture = unsafeBitCast(base.start(), to: FBFuture<AnyObject>.self)
    }
    return unsafeBitCast(
      startFuture
        .onQueue(
          queue,
          map: { task -> AnyObject in
            logger?.log("Task started \(task) for xcodebuild \(arguments.joined(separator: " "))")
            return task
          }),
      to: FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>.self
    )
  }

  // MARK: Public Methods

  @objc public static func xctestRunProperties(_ testLaunch: FBTestLaunchConfiguration) -> [String: Any] {
    return [
      "StubBundleId": [
        "TestHostPath": testLaunch.testHostBundle?.path as Any,
        "TestBundlePath": testLaunch.testBundle.path,
        "UseUITargetAppProvidedByTests": true,
        "IsUITestBundle": true,
        "CommandLineArguments": testLaunch.applicationLaunchConfiguration.arguments,
        "EnvironmentVariables": testLaunch.applicationLaunchConfiguration.environment,
        "TestingEnvironmentVariables": [
          "DYLD_FRAMEWORK_PATH": "__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
          "DYLD_LIBRARY_PATH": "__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
        ],
      ] as [String: Any]
    ]
  }

  @objc public static func createXCTestRunFile(at directory: String, fromConfiguration configuration: FBTestLaunchConfiguration) throws -> String {
    let fileName = ProcessInfo.processInfo.globallyUniqueString.appending(".xctestrun")
    let path = (directory as NSString).appendingPathComponent(fileName)

    let defaultTestRunProperties = FBXcodeBuildOperation.xctestRunProperties(configuration)

    let testRunProperties: NSDictionary
    if let xcTestRunProps = configuration.xcTestRunProperties {
      testRunProperties = FBXcodeBuildOperation.overwriteXCTestRunProperties(withBaseProperties: xcTestRunProps, newProperties: defaultTestRunProperties)
    } else {
      testRunProperties = defaultTestRunProperties as NSDictionary
    }

    if !testRunProperties.write(toFile: path, atomically: false) {
      throw XCTestBootstrapError.describe("Failed to write to file \(path)").build()
    }
    return path
  }

  @objc public static func terminateAbandonedXcodebuildProcesses(forUDID udid: String, processFetcher: FBProcessFetcher, queue: DispatchQueue, logger: FBControlCoreLogger) -> FBFuture<NSArray> {
    let processes = FBXcodeBuildOperation.activeXcodebuildProcesses(forUDID: udid, processFetcher: processFetcher)
    if processes.isEmpty {
      logger.log("No processes for \(udid) to terminate")
      return FBFuture(result: NSArray())
    }
    logger.log("Terminating abandoned xcodebuild processes \(FBCollectionInformation.oneLineDescription(from: processes))")
    let strategy = FBProcessTerminationStrategy.strategy(withProcessFetcher: processFetcher, workQueue: queue, logger: logger)
    var futures: [AnyObject] = []
    for process in processes {
      let termination = unsafeBitCast(strategy.killProcessIdentifier(process.processIdentifier), to: FBFuture<AnyObject>.self).mapReplace(process)
      futures.append(termination as AnyObject)
    }
    // futureWithFutures: is NS_SWIFT_UNAVAILABLE, use ObjC runtime
    let selector = NSSelectorFromString("futureWithFutures:")
    let cls: AnyClass = FBFuture<NSArray>.self
    let method = (cls as AnyObject).method(for: selector)
    typealias CombineFunc = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<NSArray>
    let combine = unsafeBitCast(method, to: CombineFunc.self)
    return combine(cls as AnyObject, selector, futures as NSArray)
  }

  @objc(xcodeBuildPathWithError:) public static func xcodeBuildPath() throws -> String {
    let path = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("/usr/bin/xcodebuild")
    if !FileManager.default.fileExists(atPath: path) {
      throw XCTestBootstrapError.describe("xcodebuild does not exist at expected path \(path)").build()
    }
    return path
  }

  @objc public static func overwriteXCTestRunProperties(withBaseProperties baseProperties: [String: Any], newProperties: [String: Any]) -> NSDictionary {
    let defaultTestProperties = newProperties["StubBundleId"] as? [String: Any] ?? [:]
    var mutableTestRunProperties: [String: Any] = [:]
    for (testId, value) in baseProperties {
      guard var mutableTestProperties = value as? [String: Any] else { continue }
      for (key, newValue) in defaultTestProperties {
        if mutableTestProperties[key] != nil {
          mutableTestProperties[key] = newValue
        }
      }
      mutableTestRunProperties[testId] = mutableTestProperties
    }
    return mutableTestRunProperties as NSDictionary
  }

  @objc public static func confirmExit(ofXcodebuildOperation task: FBSubprocess<AnyObject, AnyObject, AnyObject>, configuration: FBTestLaunchConfiguration, reporter: FBXCTestReporter, target: FBiOSTarget, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
    return unsafeBitCast(
      unsafeBitCast(
        task.exited(withCodes: [0, 65]),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        target.workQueue,
        respondToCancellation: { () -> FBFuture<NSNull> in
          return unsafeBitCast(
            task.sendSignal(SIGTERM, backingOffToKillWithTimeout: 1, logger: logger),
            to: FBFuture<NSNull>.self
          )
        }
      )
      .onQueue(
        target.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          logger.log("xcodebuild operation completed successfully \(task)")
          if let resultBundlePath = configuration.resultBundlePath {
            return unsafeBitCast(
              FBXCTestResultBundleParser.parse(resultBundlePath, target: target, reporter: reporter, logger: logger, extractScreenshots: configuration.reportResultBundle),
              to: FBFuture<AnyObject>.self
            )
          }
          logger.log("No result bundle to parse")
          return FBFuture(result: NSNull() as AnyObject)
        }
      )
      .onQueue(
        target.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          logger.log("Reporting test results")
          reporter.didFinishExecutingTestPlan()
          return FBFuture(result: NSNull() as AnyObject)
        }),
      to: FBFuture<NSNull>.self
    )
  }

  // MARK: Private

  private static func activeXcodebuildProcesses(forUDID udid: String, processFetcher: FBProcessFetcher) -> [FBProcessInfo] {
    let xcodebuildProcesses = processFetcher.processes(withProcessName: "xcodebuild")
    var relevantProcesses: [FBProcessInfo] = []
    for process in xcodebuildProcesses {
      guard let targetUDID = process.environment[XcodebuildEnvironmentTargetUDID], targetUDID == udid else {
        continue
      }
      relevantProcesses.append(process)
    }
    return relevantProcesses
  }
}
