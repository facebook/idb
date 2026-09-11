/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

enum ListTestError: Error {
  case testNamesMalformed(result: String)
  case missingShimAndOutput(result: String)
  case testProcessMissingExitCode(result: String)
  case testListJSONParseFailed
  case unexpectedTestName(value: String)
  case listingFailed(exitCode: Int32, exitDescription: String, stdErr: String)
}

extension ListTestError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .testNamesMalformed(result):
      return "Expected a list of test names, got \(result)"
    case let .missingShimAndOutput(result):
      return "Expected the shim path and its output file, got \(result)"
    case let .testProcessMissingExitCode(result):
      return "Expected the test process to resolve to its exit code, got \(result)"
    case .testListJSONParseFailed:
      return "Failed to parse test list JSON"
    case let .unexpectedTestName(value):
      return "Received unexpected test name from shim: \(value)"
    case let .listingFailed(exitCode, exitDescription, stdErr):
      return "Listing of tests failed due to xctest binary exiting with non-zero exit code \(exitCode) [\(exitDescription)]: \(stdErr)"
    }
  }
}

private final class ListTestStrategy_ReporterWrapped: XCTestRunner {

  let strategy: FBListTestStrategy
  let reporter: FBXCTestReporter

  init(strategy: FBListTestStrategy, reporter: FBXCTestReporter) {
    self.strategy = strategy
    self.reporter = reporter
  }

  func execute() -> FBFuture<NSNull> {
    reporter.didBeginExecutingTestPlan()

    return
      strategy.listTests()
      .onQueue(
        strategy.target.workQueue,
        fmap: { testNamesObj -> FBFuture<AnyObject> in
          guard let testNames = testNamesObj as? [String] else {
            return FBFuture(error: ListTestError.testNamesMalformed(result: String(describing: testNamesObj)))
          }
          for testName in testNames {
            guard let slashRange = testName.range(of: "/") else { continue }
            let className = String(testName[testName.startIndex..<slashRange.lowerBound])
            let methodName = String(testName[slashRange.upperBound...])
            self.reporter.testCaseDidStart(forTestClass: className, method: methodName)
            self.reporter.testCaseDidFinish(forTestClass: className, method: methodName, with: .passed, duration: 0, logs: nil)
          }
          self.reporter.didFinishExecutingTestPlan()
          return FBFuture<AnyObject>(result: NSNull())
        }
      )
      .retyped(FBFuture<NSNull>.self)
  }
}

public final class FBListTestStrategy {

  let target: any LogicTestTarget
  private let configuration: FBListTestConfiguration
  private let logger: FBControlCoreLogger

  public init(target: any LogicTestTarget, configuration: FBListTestConfiguration, logger: FBControlCoreLogger) {
    self.target = target
    self.configuration = configuration
    self.logger = logger
  }

  public func listTests() -> FBFuture<NSArray> {
    let shimBuffer = FBDataBuffer.consumableBuffer()
    let target = self.target
    let shimFuture: FBFuture<AnyObject> = fbFutureFromAsync {
      try await target.xctest.extendedTestShim() as AnyObject
    }
    let futures: [FBFuture<AnyObject>] = [
      shimFuture,
      FBProcessOutput<NSNull>(for: shimBuffer).providedThroughFile().retyped(FBFuture<AnyObject>.self),
    ]
    let combined = FBFuture<AnyObject>.combine(futures)

    return
      combined
      .onQueue(
        target.workQueue,
        fmap: { tupleObj -> FBFuture<AnyObject> in
          let tuple = tupleObj as [AnyObject]
          guard tuple.count == 2,
            let shimPath = tuple[0] as? String,
            let shimOutput = tuple[1] as? FBProcessFileOutput
          else {
            return FBFuture(error: ListTestError.missingShimAndOutput(result: String(describing: tuple)))
          }
          return self.listTests(withShimPath: shimPath, shimOutput: shimOutput, shimBuffer: shimBuffer)
            .retyped(FBFuture<AnyObject>.self)
        }
      )
      .retyped(FBFuture<NSArray>.self)
  }

  func wrapInReporter(_ reporter: FBXCTestReporter) -> XCTestRunner {
    ListTestStrategy_ReporterWrapped(strategy: self, reporter: reporter)
  }

  // MARK: - Private

  private func listTests(withShimPath shimPath: String, shimOutput: FBProcessFileOutput, shimBuffer: FBConsumableBuffer) -> FBFuture<NSArray> {
    let stdOutBuffer = FBDataBuffer.consumableBuffer()
    let stdOutConsumer: FBDataConsumer = FBCompositeDataConsumer(consumers: [
      stdOutBuffer,
      FBLoggingDataConsumer(logger: logger),
    ])
    let stdErrBuffer = FBDataBuffer.consumableBuffer()
    let stdErrConsumer: FBDataConsumer = FBCompositeDataConsumer(consumers: [
      stdErrBuffer,
      FBLoggingDataConsumer(logger: logger),
    ])

    // The temporary directory is scoped to the inner pipeline: the async wrapper holds it open
    // until the future chain resolves, exactly as the popped context did.
    return
      fbFutureFromAsync {
        try await FBTemporaryDirectory(logger: self.logger).withTemporaryDirectory { temporaryDirectoryURL in
          let libraries = try await OToolDynamicLibs.findFullPath(forSanitiserDyldInBundle: self.configuration.testBundlePath)
          let environment = FBListTestStrategy.setupEnvironment(withDylibs: libraries, shimPath: shimPath, shimOutputFilePath: shimOutput.filePath, bundlePath: self.configuration.testBundlePath, target: self.target)
          return try await bridgeFBFuture(
            FBListTestStrategy.listTestProcess(withTarget: self.target, configuration: self.configuration, xctestPath: self.target.xctest.path, environment: environment, stdOutConsumer: stdOutConsumer, stdErrConsumer: stdErrConsumer, logger: self.logger, temporaryDirectory: temporaryDirectoryURL)
              .onQueue(
                self.target.workQueue,
                fmap: { exitCodeFutureObj -> FBFuture<AnyObject> in
                  guard let exitCodeFuture = exitCodeFutureObj as? FBFuture<NSNumber> else {
                    return FBFuture(error: ListTestError.testProcessMissingExitCode(result: String(describing: exitCodeFutureObj)))
                  }
                  return FBListTestStrategy.launchedProcess(
                    withExitCode: exitCodeFuture, shimOutput: shimOutput, shimBuffer: shimBuffer, stdOutBuffer: stdOutBuffer, stdErrBuffer: stdErrBuffer, queue: self.target.workQueue
                  ).retyped(FBFuture<AnyObject>.self)
                }))
        }
      }
      .retyped(FBFuture<NSArray>.self)
  }

  private static func setupEnvironment(withDylibs libraries: [String], shimPath: String, shimOutputFilePath: String, bundlePath: String, target: any FBiOSTarget) -> [String: String] {
    var librariesWithShim = [shimPath]
    librariesWithShim.append(contentsOf: libraries)

    var environment: [String: String] = [
      "DYLD_INSERT_LIBRARIES": librariesWithShim.joined(separator: ":"),
      "TEST_SHIM_OUTPUT_PATH": shimOutputFilePath,
      "TEST_SHIM_BUNDLE_PATH": bundlePath,
    ]

    for (key, value) in target.environmentAdditions() {
      environment[key] = value
    }

    return environment
  }

  private static func launchedProcess(withExitCode exitCode: FBFuture<NSNumber>, shimOutput: FBProcessFileOutput, shimBuffer: FBConsumableBuffer, stdOutBuffer: FBConsumableBuffer, stdErrBuffer: FBConsumableBuffer, queue: DispatchQueue) -> FBFuture<NSArray> {
    return
      shimOutput.startReading().retyped(FBFuture<AnyObject>.self)
      .onQueue(
        queue,
        fmap: { _ -> FBFuture<AnyObject> in
          FBListTestStrategy.onQueue(
            queue, confirmExit: exitCode, closingOutput: shimOutput, shimBuffer: shimBuffer, stdOutBuffer: stdOutBuffer, stdErrBuffer: stdErrBuffer
          ).retyped(FBFuture<AnyObject>.self)
        }
      )
      .onQueue(
        queue,
        fmap: { _ -> FBFuture<AnyObject> in
          let data = shimBuffer.data()
          let tests: [[String: String]]
          do {
            guard let parsed = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: String]] else {
              NSLog("Shimulator buffer data (should contain test information): %@", String(data: data, encoding: .utf8) ?? "")
              return FBFuture<AnyObject>(error: ListTestError.testListJSONParseFailed)
            }
            tests = parsed
          } catch {
            NSLog("Shimulator buffer data (should contain test information): %@", String(data: data, encoding: .utf8) ?? "")
            return FBFuture<AnyObject>(error: error)
          }
          var testNames: [String] = []
          for test in tests {
            guard let testName = test["legacyTestName"] else {
              return FBFuture(error: ListTestError.unexpectedTestName(value: String(describing: test["legacyTestName"])))
            }
            testNames.append(testName)
          }
          return FBFuture(result: testNames as NSArray as AnyObject)
        }
      )
      .retyped(FBFuture<NSArray>.self)
  }

  private static func onQueue(_ queue: DispatchQueue, confirmExit exitCode: FBFuture<NSNumber>, closingOutput output: FBProcessFileOutput, shimBuffer: FBConsumableBuffer, stdOutBuffer: FBConsumableBuffer, stdErrBuffer: FBConsumableBuffer) -> FBFuture<NSNull> {
    return
      exitCode
      .onQueue(
        queue,
        fmap: { exitCodeNumber -> FBFuture<AnyObject> in
          let exitCodeValue = exitCodeNumber.int32Value
          if let description = XCTestProcess.describeFailingExitCode(exitCodeValue) {
            let stdErrReversed = stdErrBuffer.lines().reversed().joined(separator: "\n")
            return FBFuture(error: ListTestError.listingFailed(exitCode: exitCodeValue, exitDescription: description, stdErr: stdErrReversed))
          }
          let futures: [FBFuture<AnyObject>] = [
            output.stopReading().retyped(FBFuture<AnyObject>.self),
            shimBuffer.finishedConsuming.retyped(FBFuture<AnyObject>.self),
          ]
          return FBFuture<AnyObject>.combine(futures).retyped(FBFuture<AnyObject>.self)
        }
      )
      .retyped(FBFuture<NSNull>.self)
  }

  private static func listTestProcess(withTarget target: any LogicTestTarget, configuration: FBListTestConfiguration, xctestPath: String, environment: [String: String], stdOutConsumer: FBDataConsumer, stdErrConsumer: FBDataConsumer, logger: FBControlCoreLogger, temporaryDirectory: URL) -> FBFuture<AnyObject> {
    var launchPath = xctestPath
    var env = environment

    let stdOut = FBProcessOutput<AnyObject>(for: stdOutConsumer)
    let stdErr = FBProcessOutput<AnyObject>(for: stdErrConsumer)
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: stdOut, stdErr: stdErr)

    if let runnerAppPath = configuration.runnerAppPath, FBBundleDescriptor.isApplication(atPath: runnerAppPath) {
      let developerLibraryPath = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/Library")
      let testFrameworkPaths = [
        (developerLibraryPath as NSString).appendingPathComponent("Frameworks"),
        (developerLibraryPath as NSString).appendingPathComponent("PrivateFrameworks"),
      ]
      env["DYLD_FALLBACK_FRAMEWORK_PATH"] = testFrameworkPaths.joined(separator: ":")
      env["DYLD_FALLBACK_LIBRARY_PATH"] = testFrameworkPaths.joined(separator: ":")

      let appBundle: FBBundleDescriptor
      do {
        appBundle = try FBBundleDescriptor.bundle(fromPath: runnerAppPath)
      } catch {
        return FBFuture<AnyObject>(error: error)
      }
      launchPath = appBundle.binary?.path ?? launchPath
      let spawnConfiguration = FBProcessSpawnConfiguration(launchPath: launchPath, arguments: [], environment: env, io: io, mode: .default)
      return FBListTestStrategy.listTestProcess(withSpawnConfiguration: spawnConfiguration, onTarget: target, timeout: configuration.testTimeout, logger: logger)
    } else {
      let spawnConfiguration = FBProcessSpawnConfiguration(launchPath: launchPath, arguments: [], environment: env, io: io, mode: .default)

      return fbFutureFromAsync {
        let mappedConfig = try await FBArchitectureProcessAdapter.adaptProcessConfiguration(spawnConfiguration, toAnyArchitectureIn: Set(configuration.architectures.map { FBArchitecture(rawValue: $0) }), temporaryDirectory: temporaryDirectory)
        return try await bridgeFBFuture(
          FBListTestStrategy.listTestProcess(withSpawnConfiguration: mappedConfig, onTarget: target, timeout: configuration.testTimeout, logger: logger))
      }
    }
  }

  private static func listTestProcess(withSpawnConfiguration spawnConfiguration: FBProcessSpawnConfiguration, onTarget target: any LogicTestTarget, timeout: TimeInterval, logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    let launchFuture: FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> = fbFutureFromAsync {
      try await target.processSpawn.launchProcess(spawnConfiguration)
    }
    return
      launchFuture
      .onQueue(
        target.workQueue,
        map: { process -> AnyObject in
          XCTestProcess.ensureProcess(process, completesWithin: timeout, crashLogCommands: nil, queue: target.workQueue, logger: logger) as AnyObject
        })
  }
}
