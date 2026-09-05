/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Operation duration.
public let DefaultInstrumentsOperationDuration: TimeInterval = 60 * 60 * 4
/// When stopping instruments with SIGINT, wait this long before SIGKILLing it.
public let DefaultInstrumentsTerminateTimeout: TimeInterval = 600.0
/// Wait this long to ensure instruments started properly.
public let DefaultInstrumentsLaunchRetryTimeout: TimeInterval = 360.0
/// The pause between launch attempts.
private let LaunchRetryInterval: UInt64 = 100 * NSEC_PER_MSEC
/// Fail instruments if the launch error message appears within this timeout.
public let DefaultInstrumentsLaunchErrorTimeout: TimeInterval = 15.0

public enum FBInstrumentsError: Error {
  case outputDirectoryCreationFailed(underlying: Error)
  case startupFailed(logs: [String])
  case launchTimedOut(timeout: TimeInterval)
  case exitedWithFailure(exitCode: NSNumber)
}

extension FBInstrumentsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .outputDirectoryCreationFailed(underlying):
      return "Failed to create instruments trace output directory: \(underlying)"
    case let .startupFailed(logs):
      return "Instruments did not start properly. Instruments logs:\n\(logs.joined(separator: "\n"))"
    case let .launchTimedOut(timeout):
      return String(format: "Timed out after %f seconds waiting for successful instruments startup", timeout)
    case let .exitedWithFailure(exitCode):
      return "Instruments exited with failure - status: \(exitCode)"
    }
  }
}

/// Watches the instruments output for the two lifecycle markers: template loading has
/// begun, and the premature "Trace Complete" that signals a failed startup.
final class InstrumentsConsumer: NSObject, FBDataConsumer {

  let hasStoppedRecording: FBMutableFuture<NSNull>
  let hasStartedLoadingTemplate: FBMutableFuture<NSNull>
  private let lineConsumer: any FBDataConsumer

  override init() {
    // Lines arrive serially on the consumer's queue, so `logs` needs no synchronization. Captured
    // locals avoid a consumer -> block -> self cycle.
    final class Logs {
      var lines: [String] = []
    }
    let hasStoppedRecording = FBMutableFuture<NSNull>()
    let hasStartedLoadingTemplate = FBMutableFuture<NSNull>()
    let logs = Logs()
    self.hasStoppedRecording = hasStoppedRecording
    self.hasStartedLoadingTemplate = hasStartedLoadingTemplate
    self.lineConsumer = FBBlockDataConsumer.asynchronousLineConsumer { logLine in
      if !logLine.isEmpty {
        logs.lines.append(logLine)
      }
      if logLine.contains("Loading template") {
        hasStartedLoadingTemplate.resolve(withResult: NSNull())
      }
      if logLine.contains("Instruments Trace Complete"), !hasStoppedRecording.hasCompleted {
        hasStoppedRecording.resolveWithError(FBInstrumentsError.startupFailed(logs: logs.lines))
      }
    }
    super.init()
  }

  func consumeData(_ data: Data) {
    lineConsumer.consumeData(data)
  }

  func consumeEndOfFile() {
    lineConsumer.consumeEndOfFile()
  }
}

/// Represents an operation of the instruments command-line.
public final class FBInstrumentsOperation {

  public let task: FBSubprocess<AnyObject, AnyObject, AnyObject>
  public let traceFile: URL
  public let configuration: FBInstrumentsConfiguration
  public let logger: any FBControlCoreLogger

  init(task: FBSubprocess<AnyObject, AnyObject, AnyObject>, traceFile: URL, configuration: FBInstrumentsConfiguration, logger: any FBControlCoreLogger) {
    self.task = task
    self.traceFile = traceFile
    self.configuration = configuration
    self.logger = logger
  }

  // MARK: - Lifecycle

  /// Constructs an 'instruments' operation, of indefinite length.
  ///
  /// The instruments cli is unreliable and sometimes stops recording right after starting.
  /// To make it reliable, launches are retried until one succeeds or the launch-retry
  /// timeout elapses.
  public class func operation(
    target: any FBiOSTarget,
    configuration: FBInstrumentsConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBInstrumentsOperation {
    let deadline = Date().addingTimeInterval(configuration.timings.launchRetryTimeout)
    while true {
      try Task.checkCancellation()
      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0 else {
        throw FBInstrumentsError.launchTimedOut(timeout: configuration.timings.launchRetryTimeout)
      }
      do {
        return try await startSingleAttempt(target: target, configuration: configuration, logger: logger, attemptTimeout: remaining)
      } catch is CancellationError {
        // Each attempt creates a trace directory and spawns instruments, so a cancelled caller
        // must stop the loop rather than retry until the deadline.
        throw CancellationError()
      } catch {
        try await Task.sleep(nanoseconds: LaunchRetryInterval)
      }
    }
  }

  /// Builds the `instruments` command line.
  static func launchArguments(udid: String, configuration: FBInstrumentsConfiguration, traceFile: String) -> [String] {
    // Formatted via NSNumber rather than Int: operationDuration arrives unclamped from the client,
    // and Int(_: Double) traps on a value that is infinite, NaN, or beyond Int.max.
    let durationMilliseconds = NSNumber(value: configuration.timings.operationDuration * 1000).stringValue
    var arguments: [String] = []
    arguments.append(contentsOf: configuration.toolArguments)
    arguments.append(contentsOf: ["-w", udid, "-D", traceFile, "-t", configuration.templateName, "-l", durationMilliseconds, "-v"])
    if !configuration.targetApplication.isEmpty {
      arguments.append(configuration.targetApplication)
      for (key, value) in configuration.appEnvironment {
        arguments.append(contentsOf: ["-e", key, value])
      }
      arguments.append(contentsOf: configuration.appArguments)
    }
    return arguments
  }

  private class func startSingleAttempt(
    target: any FBiOSTarget,
    configuration: FBInstrumentsConfiguration,
    logger: any FBControlCoreLogger,
    attemptTimeout: TimeInterval
  ) async throws -> FBInstrumentsOperation {
    let traceDir = (target.auxillaryDirectory as NSString).appendingPathComponent("instruments-" + UUID().uuidString)
    do {
      try FileManager.default.createDirectory(atPath: traceDir, withIntermediateDirectories: false, attributes: nil)
    } catch {
      throw FBInstrumentsError.outputDirectoryCreationFailed(underlying: error)
    }
    let traceFile = (traceDir as NSString).appendingPathComponent("trace.trace")

    let arguments = launchArguments(udid: target.udid, configuration: configuration, traceFile: traceFile)
    logger.log("Starting instruments with arguments: \(FBCollectionInformation.oneLineDescription(from: arguments))")

    let instrumentsConsumer = InstrumentsConsumer()
    let instrumentsLogger = FBControlCoreLoggerFactory.logger(to: instrumentsConsumer)
    let compositeLogger = FBControlCoreLoggerFactory.compositeLogger(with: [logger, instrumentsLogger])

    let startFuture = FBProcessBuilder<NSNull, AnyObject, AnyObject>
      .withLaunchPath("/usr/bin/instruments", arguments: arguments)
      .withStdOut(to: compositeLogger)
      .withStdErr(to: compositeLogger)
      .withTaskLifecycleLogging(to: logger)
      .start()
    let task = try await bridgeFBFuture(
      startFuture
        .timeout(attemptTimeout, waitingFor: "instruments to start")
        .retyped(FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>.self))

    let templateLoaded = convertFBMutableFuture(instrumentsConsumer.hasStartedLoadingTemplate)
      .timeout(attemptTimeout, waitingFor: "instruments to start loading the template")
    do {
      try await bridgeFBFutureVoid(templateLoaded.retyped(FBFuture<NSNull>.self))
      logger.log("Waiting for \(configuration.timings.launchErrorTimeout) seconds for instruments to start properly")
      // Instruments profiling started correctly if the timer expires before
      // 'hasStoppedRecording' resolves. This is necessary because instruments prints
      // nothing when profiling has begun; failure is detected by 'Instruments Trace
      // Complete' appearing within the launch-error timeout.
      let timerFuture = FBFuture<NSNull>.empty().delay(configuration.timings.launchErrorTimeout)
      let raced = FBFuture<AnyObject>(race: [
        convertFBMutableFuture(instrumentsConsumer.hasStoppedRecording).retyped(FBFuture<AnyObject>.self),
        timerFuture.retyped(FBFuture<AnyObject>.self),
      ])
      _ = try await bridgeFBFuture(raced)
    } catch {
      _ = try? await bridgeFBFuture(task.sendSignal(SIGTERM))
      throw error
    }

    logger.log("Started instruments \(task)")
    return FBInstrumentsOperation(task: task, traceFile: URL(fileURLWithPath: traceFile), configuration: configuration, logger: logger)
  }

  /// Stops the operation, waiting for the trace file to be written out to disk.
  /// Returns the trace file.
  public func stop() async throws -> URL {
    logger.log("Terminating instruments \(task). Backoff Timeout \(configuration.timings.terminateTimeout)")
    _ = try? await bridgeFBFuture(task.sendSignal(SIGINT, backingOffToKillWithTimeout: configuration.timings.terminateTimeout, logger: logger))
    let exitCode = try await bridgeFBFuture(task.exitCode)
    guard exitCode == 0 as NSNumber else {
      throw FBInstrumentsError.exitedWithFailure(exitCode: exitCode)
    }
    return traceFile
  }

  /// Post-processes an instruments trace, returning the post-processed trace URL.
  public class func postProcess(
    arguments: [String]?,
    traceFile: URL,
    queue: DispatchQueue,
    logger: (any FBControlCoreLogger)?
  ) async throws -> URL {
    guard let arguments, !arguments.isEmpty else {
      return traceFile
    }
    let outputTraceFile = traceFile.deletingLastPathComponent().appendingPathComponent(arguments[2])
    var launchArguments = [arguments[1], traceFile.path, "-o", outputTraceFile.path]
    if arguments.count > 3 {
      launchArguments.append(contentsOf: arguments[3...])
    }

    logger?.log("Starting post processing | Launch path: \(arguments[0]) | Arguments: \(FBCollectionInformation.oneLineDescription(from: launchArguments))")
    let builder = FBProcessBuilder<AnyObject, AnyObject, AnyObject>
      .withLaunchPath(arguments[0], arguments: launchArguments)
      .withStdInConnected()
    let runFuture: FBFuture<AnyObject>
    if let logger {
      runFuture =
        builder
        .withStdOut(to: logger)
        .withStdErr(to: logger)
        .withTaskLifecycleLogging(to: logger)
        .runUntilCompletion(withAcceptableExitCodes: [0])
        .retyped(FBFuture<AnyObject>.self)
    } else {
      runFuture =
        builder
        .runUntilCompletion(withAcceptableExitCodes: [0])
        .retyped(FBFuture<AnyObject>.self)
    }
    _ = try await bridgeFBFuture(runFuture)
    return outputTraceFile
  }
}
