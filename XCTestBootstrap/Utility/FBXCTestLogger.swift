/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let fbxctestOutputLogDirectoryEnv = "FBXCTEST_LOG_DIRECTORY"
private let xctoolOutputLogDirectoryEnv = "XCTOOL_TEST_ENV_FB_LOG_DIRECTORY"

// SAFETY: all stored state is immutable; thread-safety of logging delegates to the base logger,
// which the FBControlCoreLogger contract requires to be thread-safe.
/// The way log mirroring fails when the writer is not a consumer, as data rather than an assembled string.
public enum FBXCTestLoggerError: Error, LocalizedError {
  case notADataConsumer(path: String, writer: String)

  public var errorDescription: String? {
    switch self {
    case let .notADataConsumer(path, writer):
      return "Expected a data consumer writing to \(path), got \(writer)"
    }
  }
}

public final class FBXCTestLogger: NSObject, FBControlCoreLogger, @unchecked Sendable {

  private let baseLogger: FBControlCoreLogger
  public let logDirectory: String

  private init(baseLogger: FBControlCoreLogger, logDirectory: String) {
    self.baseLogger = baseLogger
    self.logDirectory = logDirectory
    super.init()
  }

  // MARK: Factory Methods

  private static func defaultLogDirectory() -> String {
    let env = ProcessInfo.processInfo.environment
    if let directory = env[fbxctestOutputLogDirectoryEnv] {
      return directory
    }
    if let directory = env[xctoolOutputLogDirectoryEnv] {
      return directory
    }
    let directory = FileManager.default.currentDirectoryPath.appending("/tmp")
    if FileManager.default.fileExists(atPath: directory) {
      return directory
    }
    return NSTemporaryDirectory()
  }

  private static func defaultLogName() -> String {
    "\(ProcessInfo.processInfo.globallyUniqueString)_test.log"
  }

  public static func defaultLoggerInDefaultDirectory() -> FBXCTestLogger {
    loggerInDefaultDirectory(defaultLogName())
  }

  public static func loggerInDefaultDirectory(_ name: String) -> FBXCTestLogger {
    logger(inDirectory: defaultLogDirectory(), name: name)
  }

  public static func defaultLogger(inDirectory directory: String) -> FBXCTestLogger {
    logger(inDirectory: directory, name: defaultLogName())
  }

  public static func logger(inDirectory directory: String, name: String) -> FBXCTestLogger {
    let success = (try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)) != nil
    assert(success, "Expected to create directory at path \(directory)")

    let path = (directory as NSString).appendingPathComponent(name)
    do {
      try Data().write(to: URL(fileURLWithPath: path))
    } catch {
      NSLog("Failed to create log file at path %@: %@", path, error.localizedDescription)
    }
    let stderrLogger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: true).withDateFormatEnabled(true)
    guard let fileHandle = FileHandle(forWritingAtPath: path) else {
      NSLog("Failed to open the log file at path %@ for writing, logging to stderr only", path)
      return FBXCTestLogger(baseLogger: stderrLogger, logDirectory: directory)
    }

    let baseLogger = FBControlCoreLoggerFactory.compositeLogger(with: [
      stderrLogger,
      FBControlCoreLoggerFactory.logger(toFileDescriptor: fileHandle.fileDescriptor, closeOnEndOfFile: false).withDateFormatEnabled(true),
    ])

    return FBXCTestLogger(baseLogger: baseLogger, logDirectory: directory)
  }

  // MARK: FBControlCoreLogger

  @discardableResult
  public func log(_ string: String) -> FBControlCoreLogger {
    baseLogger.log(string)
    return self
  }

  public func info() -> FBControlCoreLogger {
    FBXCTestLogger(baseLogger: baseLogger.info(), logDirectory: logDirectory)
  }

  public func debug() -> FBControlCoreLogger {
    FBXCTestLogger(baseLogger: baseLogger.debug(), logDirectory: logDirectory)
  }

  public func error() -> FBControlCoreLogger {
    FBXCTestLogger(baseLogger: baseLogger.error(), logDirectory: logDirectory)
  }

  public func withName(_ prefix: String) -> FBControlCoreLogger {
    FBXCTestLogger(baseLogger: baseLogger.withName(prefix), logDirectory: logDirectory)
  }

  public func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger {
    FBXCTestLogger(baseLogger: baseLogger.withDateFormatEnabled(enabled), logDirectory: logDirectory)
  }

  public var name: String? {
    baseLogger.name
  }

  public var level: FBControlCoreLogLevel {
    baseLogger.level
  }

  // MARK: Log Consumption

  public func logConsumption(of consumer: FBDataConsumer, toFileNamed fileName: String, logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    let queue = DispatchQueue.global(qos: .userInitiated)
    let filePath = (logDirectory as NSString).appendingPathComponent(fileName)

    return FBFileWriter.asyncWriter(forFilePath: filePath).onQueue(
      queue,
      fmap: { writer -> FBFuture<AnyObject> in
        guard let writer = writer as? FBDataConsumer else {
          return FBFuture(error: FBXCTestLoggerError.notADataConsumer(path: filePath, writer: String(describing: writer)))
        }
        logger.info().log("Mirroring output to \(filePath)")
        return FBFuture<AnyObject>(
          result: FBCompositeDataConsumer(consumers: [
            consumer,
            writer,
            FBLoggingDataConsumer(logger: logger),
          ]))
      })
  }
}
