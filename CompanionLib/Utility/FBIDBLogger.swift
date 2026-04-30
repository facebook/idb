/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation

nonisolated(unsafe) private let globalLoggers: NSMutableArray = NSMutableArray()
private let globalLoggersLock = NSLock()

private func addGlobalLogger(_ logger: FBControlCoreLogger) {
  globalLoggersLock.lock()
  globalLoggers.add(logger)
  globalLoggersLock.unlock()
}

private func removeGlobalLogger(_ logger: FBControlCoreLogger) {
  globalLoggersLock.lock()
  globalLoggers.remove(logger)
  globalLoggersLock.unlock()
}

private class FBIDBLoggerOperation: NSObject, FBLogOperation {
  let consumer: FBDataConsumer
  let logger: FBControlCoreLogger
  let queue: DispatchQueue

  init(consumer: FBDataConsumer, logger: FBControlCoreLogger, queue: DispatchQueue) {
    self.consumer = consumer
    self.logger = logger
    self.queue = queue
    super.init()
  }

  var completed: FBFuture<NSNull> {
    let logger = self.logger
    let cls = unsafeBitCast(NSClassFromString("FBMutableFuture")!, to: NSObject.Type.self)
    let mutableFuture = cls.perform(NSSelectorFromString("future"))!.takeUnretainedValue() as! FBFuture<NSNull>
    return mutableFuture.onQueue(
      self.queue,
      respondToCancellation: {
        removeGlobalLogger(logger)
        return FBFuture<NSNull>.empty()
      })
  }

  var operationType: String {
    "companion_log"
  }
}

@objc public final class FBIDBLogger: FBCompositeLogger {

  private static let loggerQueue: DispatchQueue = DispatchQueue(label: "com.facebook.idb.logger")

  @objc public static func logger(withUserDefaults userDefaults: UserDefaults) -> FBIDBLogger {
    let debugLogging = userDefaults.string(forKey: "-log-level")?.lowercased() == "info" ? false : true
    let systemLogger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: debugLogging)
    let loggers: NSMutableArray = NSMutableArray(object: systemLogger)

    let logFilePath = userDefaults.string(forKey: "-log-file-path")
    if let logFilePath {
      let logFileURL = URL(fileURLWithPath: logFilePath)
      do {
        try FileManager.default.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [:])
      } catch {
        systemLogger.error().log("Couldn't create log directory at \(logFileURL.deletingLastPathComponent()): \(error)")
        exit(1)
      }

      let fileDescriptor = open(logFileURL.path, O_WRONLY | O_APPEND | O_CREAT)
      if fileDescriptor == 0 {
        systemLogger.error().log("Couldn't create log file at \(logFileURL.path) \(String(cString: strerror(errno)))")
        exit(1)
      }

      loggers.add(FBControlCoreLoggerFactory.logger(toFileDescriptor: fileDescriptor, closeOnEndOfFile: true))
    }
    let logger = FBIDBLogger(loggers: loggers as! [FBControlCoreLogger]).withDateFormatEnabled(true) as! FBIDBLogger
    FBControlCoreGlobalConfiguration.defaultLogger = logger

    return logger
  }

  @objc public override init(loggers: [FBControlCoreLogger]) {
    super.init(loggers: loggers)
  }

  @objc public override var loggers: [FBControlCoreLogger] {
    var all = super.loggers
    globalLoggersLock.lock()
    let global = globalLoggers as! [FBControlCoreLogger]
    globalLoggersLock.unlock()
    all.append(contentsOf: global)
    return all
  }

  @objc public func tailToConsumer(_ consumer: FBDataConsumer) -> FBFuture<AnyObject> {
    fbFutureFromAsync { [self] in
      try await tailToConsumerAsync(consumer) as AnyObject
    }
  }

  public func tailToConsumerAsync(_ consumer: FBDataConsumer) async throws -> FBLogOperation {
    let queue = FBIDBLogger.loggerQueue
    return await withCheckedContinuation { (continuation: CheckedContinuation<FBLogOperation, Never>) in
      queue.async {
        let logger = FBControlCoreLoggerFactory.logger(to: consumer)
        let operation = FBIDBLoggerOperation(consumer: consumer, logger: logger, queue: queue)
        addGlobalLogger(logger)
        continuation.resume(returning: operation)
      }
    }
  }
}
