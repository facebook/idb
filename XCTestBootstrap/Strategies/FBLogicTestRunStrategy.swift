/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let EndOfFileFromStopReadingTimeout: TimeInterval = 5

private final class FBLogicTestRunOutputs: NSObject {
  let stdOutConsumer: FBDataConsumer & FBDataConsumerLifecycle
  let stdErrConsumer: FBDataConsumer & FBDataConsumerLifecycle
  let stdErrBuffer: FBConsumableBuffer
  let shimConsumer: FBDataConsumer & FBDataConsumerLifecycle
  let shimOutput: FBProcessFileOutput

  init(stdOutConsumer: FBDataConsumer & FBDataConsumerLifecycle, stdErrConsumer: FBDataConsumer & FBDataConsumerLifecycle, stdErrBuffer: FBConsumableBuffer, shimConsumer: FBDataConsumer & FBDataConsumerLifecycle, shimOutput: FBProcessFileOutput) {
    self.stdOutConsumer = stdOutConsumer
    self.stdErrConsumer = stdErrConsumer
    self.stdErrBuffer = stdErrBuffer
    self.shimConsumer = shimConsumer
    self.shimOutput = shimOutput
    super.init()
  }
}

@objc public final class FBLogicTestRunStrategy: NSObject, FBXCTestRunner {

  private let target: FBiOSTarget & AsyncProcessSpawnCommands & AsyncXCTestExtendedCommands
  private let configuration: FBLogicTestConfiguration
  private let reporter: FBLogicXCTestReporter
  private let logger: FBControlCoreLogger

  public init(target: FBiOSTarget & AsyncProcessSpawnCommands & AsyncXCTestExtendedCommands, configuration: FBLogicTestConfiguration, reporter: FBLogicXCTestReporter, logger: FBControlCoreLogger) {
    self.target = target
    self.configuration = configuration
    self.reporter = reporter
    self.logger = logger
    super.init()
  }

  // MARK: FBXCTestRunner

  @objc public func execute() -> FBFuture<NSNull> {
    return testFuture()
  }

  // MARK: Private

  private func testFuture() -> FBFuture<NSNull> {
    let uuid = UUID()

    let target = self.target
    let shimFuture: FBFuture<AnyObject> = fbFutureFromAsync {
      try await target.extendedTestShim() as AnyObject
    }
    let futures: [FBFuture<AnyObject>] = [
      buildOutputs(forUUID: uuid),
      shimFuture,
    ]

    return unsafeBitCast(
      FBFuture<AnyObject>.combine(futures)
        .onQueue(
          target.workQueue,
          fmap: { tupleObj -> FBFuture<AnyObject> in
            let tuple = tupleObj as [AnyObject]
            let outputs = tuple[0] as! FBLogicTestRunOutputs
            let shimPath = tuple[1] as! String
            return unsafeBitCast(
              self.testFuture(withOutputs: outputs, shimPath: shimPath, uuid: uuid),
              to: FBFuture<AnyObject>.self
            )
          }),
      to: FBFuture<NSNull>.self
    )
  }

  private func testFuture(withOutputs outputs: FBLogicTestRunOutputs, shimPath: String, uuid: UUID) -> FBFuture<NSNull> {
    logger.log("Starting Logic Test execution of \(configuration)")
    reporter.didBeginExecutingTestPlan()

    let xctestPath = target.xctestPath
    let testSpecifier = configuration.testFilter ?? "All"
    let launchPath = xctestPath
    let arguments = ["-XCTest", testSpecifier, configuration.testBundlePath]

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
              let environment = FBLogicTestRunStrategy.setupEnvironment(withDylibs: self.configuration.processUnderTestEnvironment, withLibraries: libraries, shimOutputFilePath: outputs.shimOutput.filePath, shimPath: shimPath, bundlePath: self.configuration.testBundlePath, coverageConfiguration: self.configuration.coverageConfiguration, logDirectoryPath: self.configuration.logDirectoryPath, waitForDebugger: self.configuration.waitForDebugger, target: self.target)

              return self.startTestProcess(withLaunchPath: launchPath, arguments: arguments, environment: environment, outputs: outputs, temporaryDirectory: temporaryDirectoryURL as URL)
                .onQueue(
                  self.target.workQueue,
                  fmap: { exitCodeFutureObj -> FBFuture<AnyObject> in
                    let exitCodeFuture = exitCodeFutureObj as! FBFuture<NSNumber>
                    return unsafeBitCast(
                      self.completeLaunchedProcess(exitCodeFuture, outputs: outputs),
                      to: FBFuture<AnyObject>.self
                    )
                  })
            })
        }),
      to: FBFuture<NSNull>.self
    )
  }

  private static func setupEnvironment(withDylibs environment: [String: String], withLibraries libraries: [String], shimOutputFilePath: String, shimPath: String, bundlePath: String, coverageConfiguration: FBCodeCoverageConfiguration?, logDirectoryPath: String?, waitForDebugger: Bool, target: FBiOSTarget) -> [String: String] {
    var librariesWithShim = [shimPath]
    librariesWithShim.append(contentsOf: libraries)

    var environmentAdditions: [String: String] = [
      "DYLD_INSERT_LIBRARIES": librariesWithShim.joined(separator: ":"),
      "TEST_SHIM_STDOUT_PATH": shimOutputFilePath,
      "TEST_SHIM_BUNDLE_PATH": bundlePath,
      "XCTOOL_WAIT_FOR_DEBUGGER": waitForDebugger ? "YES" : "NO",
    ]

    if let coverageConfiguration {
      let continuousCoverageCollectionMode = coverageConfiguration.shouldEnableContinuousCoverageCollection ? "%c" : ""
      let coverageFile = "coverage_\((bundlePath as NSString).lastPathComponent)\(continuousCoverageCollectionMode).profraw"
      let coveragePath = (coverageConfiguration.coverageDirectory as NSString).appendingPathComponent(coverageFile)
      environmentAdditions["LLVM_PROFILE_FILE"] = coveragePath
    }

    if let logDirectoryPath {
      environmentAdditions["LOG_DIRECTORY_PATH"] = logDirectoryPath
    }

    var updatedEnvironment = environment
    for (key, value) in environmentAdditions {
      updatedEnvironment[key] = value
    }
    for (key, value) in target.environmentAdditions() {
      updatedEnvironment[key] = value
    }

    return updatedEnvironment
  }

  private func completeLaunchedProcess(_ exitCode: FBFuture<NSNumber>, outputs: FBLogicTestRunOutputs) -> FBFuture<NSNull> {
    let logger = self.logger
    let reporter = self.reporter
    let queue = target.workQueue

    logger.log("Starting to read shim output from location \(outputs.shimOutput.filePath)")

    return unsafeBitCast(
      unsafeBitCast(outputs.shimOutput.startReading(), to: FBFuture<AnyObject>.self)
        .onQueue(
          queue,
          fmap: { _ -> FBFuture<AnyObject> in
            logger.log("Shim output at \(outputs.shimOutput.filePath) has been opened for reading, waiting for xctest process to exit")
            return unsafeBitCast(
              self.waitForSuccessfulCompletion(exitCode, closingOutputs: outputs),
              to: FBFuture<AnyObject>.self
            )
          }
        )
        .onQueue(
          queue,
          map: { _ -> AnyObject in
            logger.log("Normal exit of xctest process")
            reporter.didFinishExecutingTestPlan()
            return NSNull()
          }
        )
        .onQueue(
          queue,
          handleError: { error -> FBFuture<AnyObject> in
            logger.log("Abnormal exit of xctest process \(error)")
            reporter.didCrashDuringTest(error as NSError)
            return FBFuture(error: error) as! FBFuture<AnyObject>
          }),
      to: FBFuture<NSNull>.self
    )
  }

  private func waitForSuccessfulCompletion(_ exitCode: FBFuture<NSNumber>, closingOutputs outputs: FBLogicTestRunOutputs) -> FBFuture<NSNumber> {
    let logger = self.logger
    let queue = target.workQueue

    return unsafeBitCast(
      unsafeBitCast(exitCode, to: FBFuture<AnyObject>.self)
        .onQueue(
          queue,
          chain: { _ -> FBFuture<AnyObject> in
            logger.log("xctest process terminated, Tearing down IO.")
            let futures: [FBFuture<AnyObject>] = [
              unsafeBitCast(outputs.shimOutput.stopReading(), to: FBFuture<AnyObject>.self),
              unsafeBitCast(outputs.shimConsumer.finishedConsuming, to: FBFuture<AnyObject>.self),
            ]
            let combined = FBFuture<AnyObject>.combine(futures)
            // timeout:waitingFor: is variadic, use onQueue:timeout:handler: instead
            let timedOut = combined.onQueue(
              queue, timeout: EndOfFileFromStopReadingTimeout,
              handler: {
                return FBControlCoreError.describe("Timed out waiting to receive an end-of-file after fifo has been stopped, as the process has already exited").failFuture()
              })
            return timedOut.chainReplace(unsafeBitCast(exitCode, to: FBFuture<AnyObject>.self))
          }
        )
        .onQueue(
          queue,
          fmap: { exitCodeObj -> FBFuture<AnyObject> in
            let exitCodeNumber = exitCodeObj as! NSNumber
            logger.log("xctest process terminated, exited with \(exitCodeNumber), checking status code")
            let exitCodeValue = exitCodeNumber.int32Value
            if let descriptionOfExit = FBXCTestProcess.describeFailingExitCode(exitCodeValue) {
              let stdErrReversed = outputs.stdErrBuffer.lines().reversed().joined(separator: "\n")
              return FBControlCoreError.describe("xctest process exited in failure (\(exitCodeValue)): \(descriptionOfExit) \(stdErrReversed)").failFuture()
            }
            return FBFuture(result: exitCodeNumber as AnyObject)
          }),
      to: FBFuture<NSNumber>.self
    )
  }

  private static func fromQueue(_ queue: DispatchQueue, reportWaitForDebugger waitFor: Bool, forProcessIdentifier processIdentifier: pid_t, reporter: FBLogicXCTestReporter) -> FBFuture<NSNull> {
    if !waitFor {
      return FBFuture(result: NSNull())
    }
    let waitQueue = DispatchQueue(label: "com.facebook.xctestbootstrap.debugger_wait")

    return unsafeBitCast(
      unsafeBitCast(FBProcessFetcher.waitStopSignal(forProcess: processIdentifier), to: FBFuture<AnyObject>.self)
        .onQueue(
          waitQueue,
          chain: { future -> FBFuture<AnyObject> in
            if let error = future.error {
              return XCTestBootstrapError.describe("Failed to wait test process (pid \(processIdentifier)) to receive a SIGSTOP: '\(error.localizedDescription)'").failFuture()
            }
            reporter.processWaitingForDebugger(withProcessIdentifier: processIdentifier)
            return FBFuture(result: NSNull() as AnyObject)
          }),
      to: FBFuture<NSNull>.self
    )
  }

  private func buildOutputs(forUUID udid: UUID) -> FBFuture<AnyObject> {
    let reporter = self.reporter
    let logger = self.logger
    let queue = target.workQueue
    let mirrorToLogger = (configuration.mirroring.rawValue & FBLogicTestMirrorLogs.logger.rawValue) != 0
    let mirrorToFiles = (configuration.mirroring.rawValue & FBLogicTestMirrorLogs.fileLogs.rawValue) != 0

    var shimConsumers: [FBDataConsumer] = []
    var stdOutConsumers: [FBDataConsumer] = []
    var stdErrConsumers: [FBDataConsumer] = []

    let shimReportingConsumer = FBBlockDataConsumer.asynchronousLineConsumer(
      with: queue,
      dataConsumer: { line in
        reporter.handleEventJSONData(line)
      })
    shimConsumers.append(shimReportingConsumer)

    let stdOutReportingConsumer = FBBlockDataConsumer.asynchronousLineConsumer(
      with: queue,
      consumer: { line in
        reporter.testHadOutput(line + "\n")
      })
    stdOutConsumers.append(stdOutReportingConsumer)

    let stdErrReportingConsumer = FBBlockDataConsumer.asynchronousLineConsumer(
      with: queue,
      consumer: { line in
        reporter.testHadOutput(line + "\n")
      })
    stdErrConsumers.append(stdErrReportingConsumer)
    let stdErrBuffer = FBDataBuffer.consumableBuffer()
    stdErrConsumers.append(stdErrBuffer)

    if mirrorToLogger {
      shimConsumers.append(FBLoggingDataConsumer(logger: logger))
      stdErrConsumers.append(FBLoggingDataConsumer(logger: logger))
      stdErrConsumers.append(FBLoggingDataConsumer(logger: logger))
    }

    let stdOutConsumer = FBCompositeDataConsumer(consumers: stdOutConsumers)
    let stdErrConsumer = FBCompositeDataConsumer(consumers: stdErrConsumers)
    let shimConsumer = FBCompositeDataConsumer(consumers: shimConsumers)

    var stdOutFuture: FBFuture<AnyObject> = FBFuture(result: stdOutConsumer as AnyObject)
    var stdErrFuture: FBFuture<AnyObject> = FBFuture(result: stdErrConsumer as AnyObject)
    var shimFuture: FBFuture<AnyObject> = FBFuture(result: shimConsumer as AnyObject)

    if mirrorToFiles {
      let mirrorLogger: FBXCTestLogger
      if let logDirectoryPath = configuration.logDirectoryPath {
        mirrorLogger = FBXCTestLogger.defaultLogger(inDirectory: logDirectoryPath)
      } else {
        mirrorLogger = FBXCTestLogger.defaultLoggerInDefaultDirectory()
      }
      stdOutFuture = mirrorLogger.logConsumption(of: stdOutConsumer, toFileNamed: "test_process_stdout.out", logger: logger)
      stdErrFuture = mirrorLogger.logConsumption(of: stdErrConsumer, toFileNamed: "test_process_stderr.err", logger: logger)
      shimFuture = mirrorLogger.logConsumption(of: shimConsumer, toFileNamed: "shimulator_logs.shim", logger: logger)
    }

    let futures: [FBFuture<AnyObject>] = [stdOutFuture, stdErrFuture, shimFuture]

    return FBFuture<AnyObject>.combine(futures)
      .onQueue(
        target.workQueue,
        fmap: { outputsObj -> FBFuture<AnyObject> in
          let outputsArray = outputsObj as [AnyObject]
          let resolvedStdOut = outputsArray[0] as! FBDataConsumer & FBDataConsumerLifecycle
          let resolvedStdErr = outputsArray[1] as! FBDataConsumer & FBDataConsumerLifecycle
          let resolvedShim = outputsArray[2] as! FBDataConsumer & FBDataConsumerLifecycle
          return unsafeBitCast(
            FBProcessOutput<AnyObject>(for: resolvedShim).providedThroughFile(),
            to: FBFuture<AnyObject>.self
          )
          .onQueue(
            queue,
            map: { shimOutputObj -> AnyObject in
              let shimOutput = shimOutputObj as! FBProcessFileOutput
              return FBLogicTestRunOutputs(stdOutConsumer: resolvedStdOut, stdErrConsumer: resolvedStdErr, stdErrBuffer: stdErrBuffer, shimConsumer: resolvedShim, shimOutput: shimOutput)
            })
        })
  }

  private func startTestProcess(withLaunchPath launchPath: String, arguments: [String], environment: [String: String], outputs: FBLogicTestRunOutputs, temporaryDirectory: URL) -> FBFuture<AnyObject> {
    let queue = target.workQueue
    let logger = self.logger
    let reporter = self.reporter
    let timeout = configuration.testTimeout

    logger.log("Launching xctest process with arguments \(FBCollectionInformation.oneLineDescription(from: [launchPath] + arguments)), environment \(FBCollectionInformation.oneLineDescription(from: environment))")

    let stdOut = FBProcessOutput<AnyObject>(for: outputs.stdOutConsumer)
    let stdErr = FBProcessOutput<AnyObject>(for: outputs.stdErrConsumer)
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: stdOut, stdErr: stdErr)
    let spawnConfig = FBProcessSpawnConfiguration(launchPath: launchPath, arguments: arguments, environment: environment, io: io, mode: .posixSpawn)
    let adapter = FBArchitectureProcessAdapter()

    return unsafeBitCast(
      adapter.adaptProcessConfiguration(spawnConfig, toAnyArchitectureIn: Set(configuration.architectures.map { FBArchitecture(rawValue: $0) }), queue: queue, temporaryDirectory: temporaryDirectory),
      to: FBFuture<AnyObject>.self
    )
    .onQueue(
      queue,
      fmap: { mappedConfigObj -> FBFuture<AnyObject> in
        let mappedConfig = mappedConfigObj as! FBProcessSpawnConfiguration
        let target = self.target
        let launchFuture: FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> = fbFutureFromAsync {
          try await target.launchProcess(mappedConfig)
        }
        return unsafeBitCast(launchFuture, to: FBFuture<AnyObject>.self)
      }
    )
    .onQueue(
      queue,
      map: { processObj -> AnyObject in
        let process = processObj as! FBSubprocess<AnyObject, AnyObject, AnyObject>
        let debuggerFuture = FBLogicTestRunStrategy.fromQueue(queue, reportWaitForDebugger: self.configuration.waitForDebugger, forProcessIdentifier: process.processIdentifier, reporter: reporter)
        let result = unsafeBitCast(debuggerFuture, to: FBFuture<AnyObject>.self)
          .onQueue(
            queue,
            fmap: { _ -> FBFuture<AnyObject> in
              let crashCommands = self.target as? any AsyncCrashLogCommands
              return unsafeBitCast(
                FBXCTestProcess.ensureProcess(process, completesWithin: timeout, crashLogCommands: crashCommands, queue: queue, logger: logger),
                to: FBFuture<AnyObject>.self
              )
            })
        return result as AnyObject
      })
  }
}
