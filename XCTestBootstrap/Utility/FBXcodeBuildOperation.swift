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

public enum FBXcodeBuildError: Error {
  case shimMissing
  case writeFailed(path: String)
  case xcodebuildMissing(path: String)
}

extension FBXcodeBuildError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .shimMissing:
      return "Failed to locate the shim file for xcodebuild method swizzling"
    case let .writeFailed(path):
      return "Failed to write to file \(path)"
    case let .xcodebuildMissing(path):
      return "xcodebuild does not exist at expected path \(path)"
    }
  }
}

public final class FBXcodeBuildOperation {

  // MARK: - Initializers

  public static func operation(withUDID udid: String, configuration: FBTestLaunchConfiguration, xcodeBuildPath: String, testRunFilePath: String, simDeviceSet simDeviceSetPath: String?, macOSTestShimPath: String?, queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
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
        return FBFuture(error: FBXcodeBuildError.shimMissing)
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
      startFuture = configured.start().retyped(FBFuture<AnyObject>.self)
    } else {
      startFuture = base.start().retyped(FBFuture<AnyObject>.self)
    }
    return
      startFuture
      .onQueue(
        queue,
        map: { task -> AnyObject in
          logger?.log("Task started \(task) for xcodebuild \(arguments.joined(separator: " "))")
          return task
        }
      )
      .retyped(FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>.self)
  }

  // MARK: - Public Methods

  public static func xctestRunProperties(_ testLaunch: FBTestLaunchConfiguration) -> [String: Any] {
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

  public static func createXCTestRunFile(at directory: String, fromConfiguration configuration: FBTestLaunchConfiguration) throws -> String {
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
      throw FBXcodeBuildError.writeFailed(path: path)
    }
    return path
  }

  public static func terminateAbandonedXcodebuildProcesses(forUDID udid: String, processFetcher: FBProcessFetcher, queue: DispatchQueue, logger: FBControlCoreLogger) -> FBFuture<NSArray> {
    let processes = FBXcodeBuildOperation.activeXcodebuildProcesses(forUDID: udid, processFetcher: processFetcher)
    if processes.isEmpty {
      logger.log("No processes for \(udid) to terminate")
      return FBFuture(result: NSArray())
    }
    logger.log("Terminating abandoned xcodebuild processes \(FBCollectionInformation.oneLineDescription(from: processes))")
    let strategy = FBProcessTerminationStrategy.strategy(withProcessFetcher: processFetcher, workQueue: queue, logger: logger)
    var futures: [FBFuture<AnyObject>] = []
    for process in processes {
      let termination = strategy.killProcessIdentifier(process.processIdentifier).retyped(FBFuture<AnyObject>.self).mapReplace(process)
      futures.append(termination)
    }
    return FBFuture<AnyObject>.combine(futures)
  }

  public static func xcodeBuildPath() throws -> String {
    let path = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("/usr/bin/xcodebuild")
    if !FileManager.default.fileExists(atPath: path) {
      throw FBXcodeBuildError.xcodebuildMissing(path: path)
    }
    return path
  }

  public static func overwriteXCTestRunProperties(withBaseProperties baseProperties: [String: Any], newProperties: [String: Any]) -> NSDictionary {
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

  public static func confirmExit(ofXcodebuildOperation task: FBSubprocess<AnyObject, AnyObject, AnyObject>, configuration: FBTestLaunchConfiguration, reporter: FBXCTestReporter, target: any FBiOSTarget, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
    return
      task.exited(withCodes: [0, 65]).retyped(FBFuture<AnyObject>.self)
      .onQueue(
        target.workQueue,
        respondToCancellation: { () -> FBFuture<NSNull> in
          task.sendSignal(SIGTERM, backingOffToKillWithTimeout: 1, logger: logger).retyped(FBFuture<NSNull>.self)
        }
      )
      .onQueue(
        target.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          logger.log("xcodebuild operation completed successfully \(task)")
          if let resultBundlePath = configuration.resultBundlePath {
            return FBXCTestResultBundleParser.parse(resultBundlePath, target: target, reporter: reporter, logger: logger, extractScreenshots: configuration.reportResultBundle)
              .retyped(FBFuture<AnyObject>.self)
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
        }
      )
      .retyped(FBFuture<NSNull>.self)
  }

  // MARK: - Private

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
