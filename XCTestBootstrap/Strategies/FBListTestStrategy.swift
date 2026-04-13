/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private final class FBListTestStrategy_ReporterWrapped: NSObject, FBXCTestRunner {

  let strategy: FBListTestStrategy
  let reporter: FBXCTestReporter

  init(strategy: FBListTestStrategy, reporter: FBXCTestReporter) {
    self.strategy = strategy
    self.reporter = reporter
    super.init()
  }

  func execute() -> FBFuture<NSNull> {
    reporter.didBeginExecutingTestPlan()

    return unsafeBitCast(
      unsafeBitCast(strategy.listTests(), to: FBFuture<AnyObject>.self)
        .onQueue(
          strategy.target.workQueue,
          map: { testNamesObj -> AnyObject in
            let testNames = testNamesObj as! [String]
            for testName in testNames {
              guard let slashRange = testName.range(of: "/") else { continue }
              let className = String(testName[testName.startIndex..<slashRange.lowerBound])
              let methodName = String(testName[slashRange.upperBound...])
              self.reporter.testCaseDidStart(forTestClass: className, method: methodName)
              self.reporter.testCaseDidFinish(forTestClass: className, method: methodName, with: .passed, duration: 0, logs: nil)
            }
            self.reporter.didFinishExecutingTestPlan()
            return NSNull()
          }),
      to: FBFuture<NSNull>.self
    )
  }
}

@objc public final class FBListTestStrategy: NSObject {

  let target: FBiOSTarget & FBProcessSpawnCommands & FBXCTestExtendedCommands
  private let configuration: FBListTestConfiguration
  private let logger: FBControlCoreLogger

  @objc public init(target: FBiOSTarget & FBProcessSpawnCommands & FBXCTestExtendedCommands, configuration: FBListTestConfiguration, logger: FBControlCoreLogger) {
    self.target = target
    self.configuration = configuration
    self.logger = logger
    super.init()
  }

  @objc public func listTests() -> FBFuture<NSArray> {
    let shimBuffer = FBDataBuffer.consumableBuffer()
    // futureWithFutures: is NS_SWIFT_UNAVAILABLE, use ObjC runtime
    let selector = NSSelectorFromString("futureWithFutures:")
    let cls: AnyClass = FBFuture<NSArray>.self
    let method = (cls as AnyObject).method(for: selector)
    typealias CombineFunc = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
    let combine = unsafeBitCast(method, to: CombineFunc.self)

    let futures: [AnyObject] = [
      unsafeBitCast(target.extendedTestShim(), to: FBFuture<AnyObject>.self),
      unsafeBitCast(FBProcessOutput<NSNull>(for: shimBuffer).providedThroughFile(), to: FBFuture<AnyObject>.self),
    ]
    let combined = combine(cls as AnyObject, selector, futures as NSArray)

    return unsafeBitCast(
      combined
        .onQueue(
          target.workQueue,
          fmap: { tupleObj -> FBFuture<AnyObject> in
            let tuple = tupleObj as! [AnyObject]
            let shimPath = tuple[0] as! String
            let shimOutput = tuple[1] as! FBProcessFileOutput
            return unsafeBitCast(
              self.listTests(withShimPath: shimPath, shimOutput: shimOutput, shimBuffer: shimBuffer),
              to: FBFuture<AnyObject>.self
            )
          }),
      to: FBFuture<NSArray>.self
    )
  }

  @objc public func wrapInReporter(_ reporter: FBXCTestReporter) -> FBXCTestRunner {
    return FBListTestStrategy_ReporterWrapped(strategy: self, reporter: reporter)
  }

  // MARK: Private

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

    return unsafeBitCast(
      unsafeBitCast(
        FBTemporaryDirectory(logger: logger).withTemporaryDirectory(),
        to: FBFutureContext<AnyObject>.self
      )
      .onQueue(
        target.workQueue,
        pop: { temporaryDirectory -> FBFuture<AnyObject> in
          let temporaryDirectoryURL = temporaryDirectory as! NSURL
          return unsafeBitCast(
            FBOToolDynamicLibs.findFullPath(forSanitiserDyldInBundle: self.configuration.testBundlePath, onQueue: self.target.workQueue),
            to: FBFuture<AnyObject>.self
          )
          .onQueue(
            self.target.workQueue,
            fmap: { librariesObj -> FBFuture<AnyObject> in
              let libraries = librariesObj as! [String]
              let environment = FBListTestStrategy.setupEnvironment(withDylibs: libraries, shimPath: shimPath, shimOutputFilePath: shimOutput.filePath, bundlePath: self.configuration.testBundlePath, target: self.target)

              return FBListTestStrategy.listTestProcess(withTarget: self.target, configuration: self.configuration, xctestPath: self.target.xctestPath, environment: environment, stdOutConsumer: stdOutConsumer, stdErrConsumer: stdErrConsumer, logger: self.logger, temporaryDirectory: temporaryDirectoryURL as URL)
                .onQueue(
                  self.target.workQueue,
                  fmap: { exitCodeFutureObj -> FBFuture<AnyObject> in
                    let exitCodeFuture = exitCodeFutureObj as! FBFuture<NSNumber>
                    return unsafeBitCast(
                      FBListTestStrategy.launchedProcess(withExitCode: exitCodeFuture, shimOutput: shimOutput, shimBuffer: shimBuffer, stdOutBuffer: stdOutBuffer, stdErrBuffer: stdErrBuffer, queue: self.target.workQueue),
                      to: FBFuture<AnyObject>.self
                    )
                  })
            })
        }),
      to: FBFuture<NSArray>.self
    )
  }

  private static func setupEnvironment(withDylibs libraries: [String], shimPath: String, shimOutputFilePath: String, bundlePath: String, target: FBiOSTarget) -> [String: String] {
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
    return unsafeBitCast(
      unsafeBitCast(shimOutput.startReading(), to: FBFuture<AnyObject>.self)
        .onQueue(
          queue,
          fmap: { _ -> FBFuture<AnyObject> in
            return unsafeBitCast(
              FBListTestStrategy.onQueue(queue, confirmExit: exitCode, closingOutput: shimOutput, shimBuffer: shimBuffer, stdOutBuffer: stdOutBuffer, stdErrBuffer: stdErrBuffer),
              to: FBFuture<AnyObject>.self
            )
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
                let error = NSError(domain: "FBListTestStrategy", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse test list JSON"])
                return FBFuture(error: error) as! FBFuture<AnyObject>
              }
              tests = parsed
            } catch {
              NSLog("Shimulator buffer data (should contain test information): %@", String(data: data, encoding: .utf8) ?? "")
              return FBFuture(error: error) as! FBFuture<AnyObject>
            }
            var testNames: [String] = []
            for test in tests {
              guard let testName = test["legacyTestName"] else {
                return XCTestBootstrapError.describe("Received unexpected test name from shim: \(String(describing: test["legacyTestName"]))").failFuture()
              }
              testNames.append(testName)
            }
            return FBFuture(result: testNames as NSArray as AnyObject)
          }),
      to: FBFuture<NSArray>.self
    )
  }

  private static func onQueue(_ queue: DispatchQueue, confirmExit exitCode: FBFuture<NSNumber>, closingOutput output: FBProcessFileOutput, shimBuffer: FBConsumableBuffer, stdOutBuffer: FBConsumableBuffer, stdErrBuffer: FBConsumableBuffer) -> FBFuture<NSNull> {
    return unsafeBitCast(
      unsafeBitCast(exitCode, to: FBFuture<AnyObject>.self)
        .onQueue(
          queue,
          fmap: { exitCodeObj -> FBFuture<AnyObject> in
            let exitCodeNumber = exitCodeObj as! NSNumber
            let exitCodeValue = exitCodeNumber.int32Value
            if let description = FBXCTestProcess.describeFailingExitCode(exitCodeValue) {
              let stdErrReversed = stdErrBuffer.lines().reversed().joined(separator: "\n")
              return XCTestBootstrapError.describe("Listing of tests failed due to xctest binary exiting with non-zero exit code \(exitCodeValue) [\(description)]: \(stdErrReversed)").failFuture()
            }
            // futureWithFutures: is NS_SWIFT_UNAVAILABLE, use ObjC runtime
            let selector = NSSelectorFromString("futureWithFutures:")
            let cls: AnyClass = FBFuture<NSArray>.self
            let method = (cls as AnyObject).method(for: selector)
            typealias CombineFunc = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
            let combine = unsafeBitCast(method, to: CombineFunc.self)
            let futures: [AnyObject] = [
              unsafeBitCast(output.stopReading(), to: FBFuture<AnyObject>.self) as AnyObject,
              unsafeBitCast(shimBuffer.finishedConsuming, to: FBFuture<AnyObject>.self) as AnyObject,
            ]
            return combine(cls as AnyObject, selector, futures as NSArray)
          }),
      to: FBFuture<NSNull>.self
    )
  }

  private static func listTestProcess(withTarget target: FBiOSTarget & FBProcessSpawnCommands, configuration: FBListTestConfiguration, xctestPath: String, environment: [String: String], stdOutConsumer: FBDataConsumer, stdErrConsumer: FBDataConsumer, logger: FBControlCoreLogger, temporaryDirectory: URL) -> FBFuture<AnyObject> {
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
        return FBFuture(error: error) as! FBFuture<AnyObject>
      }
      launchPath = appBundle.binary?.path ?? launchPath
      let spawnConfiguration = FBProcessSpawnConfiguration(launchPath: launchPath, arguments: [], environment: env, io: io, mode: .default)
      return FBListTestStrategy.listTestProcess(withSpawnConfiguration: spawnConfiguration, onTarget: target, timeout: configuration.testTimeout, logger: logger)
    } else {
      let spawnConfiguration = FBProcessSpawnConfiguration(launchPath: launchPath, arguments: [], environment: env, io: io, mode: .default)
      let adapter = FBArchitectureProcessAdapter()

      return unsafeBitCast(
        adapter.adaptProcessConfiguration(spawnConfiguration, toAnyArchitectureIn: Set(configuration.architectures.map { FBArchitecture(rawValue: $0) }), queue: target.workQueue, temporaryDirectory: temporaryDirectory),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        target.workQueue,
        fmap: { mappedConfigObj -> FBFuture<AnyObject> in
          let mappedConfig = mappedConfigObj as! FBProcessSpawnConfiguration
          return FBListTestStrategy.listTestProcess(withSpawnConfiguration: mappedConfig, onTarget: target, timeout: configuration.testTimeout, logger: logger)
        })
    }
  }

  private static func listTestProcess(withSpawnConfiguration spawnConfiguration: FBProcessSpawnConfiguration, onTarget target: FBiOSTarget & FBProcessSpawnCommands, timeout: TimeInterval, logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    return unsafeBitCast(target.launchProcess(spawnConfiguration), to: FBFuture<AnyObject>.self)
      .onQueue(
        target.workQueue,
        map: { processObj -> AnyObject in
          let process = processObj as! FBSubprocess<AnyObject, AnyObject, AnyObject>
          let exitCodeFuture = FBXCTestProcess.ensureProcess(process, completesWithin: timeout, crashLogCommands: nil, queue: target.workQueue, logger: logger)
          return exitCodeFuture as AnyObject
        })
  }
}
