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

enum XCTestLoggerError: Error, LocalizedError {
  case notADataConsumer(path: String, writer: String)

  public var errorDescription: String? {
    switch self {
    case let .notADataConsumer(path, writer):
      return "Expected a data consumer writing to \(path), got \(writer)"
    }
  }
}

// @unchecked Sendable: all stored state is immutable and FBControlCoreLogger implementations are required to be thread-safe.
public final class XCTestLogger: NSObject, FBControlCoreLogger, @unchecked Sendable {

  private let baseLogger: FBControlCoreLogger
  public let logDirectory: String

  private init(baseLogger: FBControlCoreLogger, logDirectory: String) {
    self.baseLogger = baseLogger
    self.logDirectory = logDirectory
    super.init()
  }

  // MARK: - Factory Methods

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

  public static func defaultLoggerInDefaultDirectory() -> XCTestLogger {
    loggerInDefaultDirectory(defaultLogName())
  }

  public static func loggerInDefaultDirectory(_ name: String) -> XCTestLogger {
    logger(inDirectory: defaultLogDirectory(), name: name)
  }

  public static func defaultLogger(inDirectory directory: String) -> XCTestLogger {
    logger(inDirectory: directory, name: defaultLogName())
  }

  public static func logger(inDirectory directory: String, name: String) -> XCTestLogger {
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
      return XCTestLogger(baseLogger: stderrLogger, logDirectory: directory)
    }

    let baseLogger = FBControlCoreLoggerFactory.compositeLogger(with: [
      stderrLogger,
      FBControlCoreLoggerFactory.logger(toFileDescriptor: fileHandle.fileDescriptor, closeOnEndOfFile: false).withDateFormatEnabled(true),
    ])

    return XCTestLogger(baseLogger: baseLogger, logDirectory: directory)
  }

  // MARK: - FBControlCoreLogger

  @discardableResult
  public func log(_ string: String) -> FBControlCoreLogger {
    baseLogger.log(string)
    return self
  }

  public func info() -> FBControlCoreLogger {
    XCTestLogger(baseLogger: baseLogger.info(), logDirectory: logDirectory)
  }

  public func debug() -> FBControlCoreLogger {
    XCTestLogger(baseLogger: baseLogger.debug(), logDirectory: logDirectory)
  }

  public func error() -> FBControlCoreLogger {
    XCTestLogger(baseLogger: baseLogger.error(), logDirectory: logDirectory)
  }

  public func withName(_ prefix: String) -> FBControlCoreLogger {
    XCTestLogger(baseLogger: baseLogger.withName(prefix), logDirectory: logDirectory)
  }

  public func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger {
    XCTestLogger(baseLogger: baseLogger.withDateFormatEnabled(enabled), logDirectory: logDirectory)
  }

  public var name: String? {
    baseLogger.name
  }

  public var level: FBControlCoreLogLevel {
    baseLogger.level
  }

  // MARK: - Log Consumption

  public func logConsumption(of consumer: FBDataConsumer, toFileNamed fileName: String, logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    let queue = DispatchQueue.global(qos: .userInitiated)
    let filePath = (logDirectory as NSString).appendingPathComponent(fileName)

    return FileWriter.asyncWriter(forFilePath: filePath).onQueue(
      queue,
      fmap: { writer -> FBFuture<AnyObject> in
        guard let writer = writer as? FBDataConsumer else {
          return FBFuture(error: XCTestLoggerError.notADataConsumer(path: filePath, writer: String(describing: writer)))
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
