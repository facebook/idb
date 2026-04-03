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

@objc public final class FBXCTestLogger: NSObject, FBControlCoreLogger {

  private let baseLogger: FBControlCoreLogger
  @objc public let logDirectory: String

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
    return "\(ProcessInfo.processInfo.globallyUniqueString)_test.log"
  }

  @objc public static func defaultLoggerInDefaultDirectory() -> FBXCTestLogger {
    return loggerInDefaultDirectory(defaultLogName())
  }

  @objc public static func loggerInDefaultDirectory(_ name: String) -> FBXCTestLogger {
    return logger(inDirectory: defaultLogDirectory(), name: name)
  }

  @objc public static func defaultLogger(inDirectory directory: String) -> FBXCTestLogger {
    return logger(inDirectory: directory, name: defaultLogName())
  }

  @objc public static func logger(inDirectory directory: String, name: String) -> FBXCTestLogger {
    let success = (try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)) != nil
    assert(success, "Expected to create directory at path \(directory)")

    let path = (directory as NSString).appendingPathComponent(name)
    try? Data().write(to: URL(fileURLWithPath: path))
    let fileHandle = FileHandle(forWritingAtPath: path)!

    let baseLogger = FBControlCoreLoggerFactory.compositeLogger(with: [
      FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: true).withDateFormatEnabled(true),
      FBControlCoreLoggerFactory.logger(toFileDescriptor: fileHandle.fileDescriptor, closeOnEndOfFile: false).withDateFormatEnabled(true),
    ])

    return FBXCTestLogger(baseLogger: baseLogger, logDirectory: directory)
  }

  // MARK: FBControlCoreLogger

  @discardableResult
  @objc public func log(_ string: String) -> FBControlCoreLogger {
    baseLogger.log(string)
    return self
  }

  @objc public func info() -> FBControlCoreLogger {
    return FBXCTestLogger(baseLogger: baseLogger.info(), logDirectory: logDirectory)
  }

  @objc public func debug() -> FBControlCoreLogger {
    return FBXCTestLogger(baseLogger: baseLogger.debug(), logDirectory: logDirectory)
  }

  @objc public func error() -> FBControlCoreLogger {
    return FBXCTestLogger(baseLogger: baseLogger.error(), logDirectory: logDirectory)
  }

  @objc public func withName(_ prefix: String) -> FBControlCoreLogger {
    return FBXCTestLogger(baseLogger: baseLogger.withName(prefix), logDirectory: logDirectory)
  }

  @objc public func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger {
    return FBXCTestLogger(baseLogger: baseLogger.withDateFormatEnabled(enabled), logDirectory: logDirectory)
  }

  @objc public var name: String? {
    return baseLogger.name
  }

  @objc public var level: FBControlCoreLogLevel {
    return baseLogger.level
  }

  // MARK: Log Consumption

  @objc public func logConsumption(of consumer: FBDataConsumer, toFileNamed fileName: String, logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    let queue = DispatchQueue.global(qos: .userInitiated)
    let filePath = (logDirectory as NSString).appendingPathComponent(fileName)

    return FBFileWriter.asyncWriter(forFilePath: filePath).onQueue(
      queue,
      map: { writer -> AnyObject in
        logger.info().log("Mirroring output to \(filePath)")
        return FBCompositeDataConsumer(consumers: [
          consumer,
          writer,
          FBLoggingDataConsumer(logger: logger),
        ])
      })
  }
}
