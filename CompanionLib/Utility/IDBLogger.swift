/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation

/// The loggers every `IDBLogger` fans out to in addition to its own, added and removed by the
/// log operations that tail the companion's output.
///
// SAFETY: `loggers` is only ever read or written inside `lock`.
// patternlint-disable-next-line unchecked-sendable
private final class GlobalLoggers: @unchecked Sendable {
  private let lock = NSLock()
  private var loggers: [ControlCoreLogger] = []

  var all: [ControlCoreLogger] {
    lock.withLock { loggers }
  }

  func add(_ logger: ControlCoreLogger) {
    lock.withLock { loggers.append(logger) }
  }

  func remove(_ logger: ControlCoreLogger) {
    lock.withLock { loggers.removeAll { $0 === logger } }
  }
}

private let globalLoggers = GlobalLoggers()

// @unchecked Sendable: all stored properties are immutable lets wrapping
// thread-safe ObjC objects.
private final class IDBLoggerOperation: LogOperation, @unchecked Sendable {
  let consumer: DataConsumer
  let logger: ControlCoreLogger

  init(consumer: DataConsumer, logger: ControlCoreLogger) {
    self.consumer = consumer
    self.logger = logger
  }

  /// Tails until cancelled, then stops delivering to the consumer.
  func waitUntilCompleted() async throws {
    do {
      try await Task.sleep(nanoseconds: .max)
    } catch {
      globalLoggers.remove(logger)
      throw error
    }
  }
}

// Restates the base class's @unchecked Sendable, as required for subclasses; it adds no stored
// state.
public final class IDBLogger: FBCompositeLogger, @unchecked Sendable {

  /// The logger the companion writes to, which is the stderr logger plus, when
  /// `-log-file-path` is given, a logger appending to that file.
  ///
  /// - Throws: `IDBLoggerError` if the log file's directory cannot be created or the file
  ///   cannot be opened. A caller handling that has `systemLogger(withUserDefaults:)` to
  ///   report it through.
  public static func logger(withUserDefaults userDefaults: UserDefaults) throws -> IDBLogger {
    var loggers: [ControlCoreLogger] = [systemLoggerSink(withUserDefaults: userDefaults)]
    if let logFilePath = userDefaults.string(forKey: "-log-file-path") {
      let fileDescriptor = try openLogFile(atPath: logFilePath)
      loggers.append(FBControlCoreLoggerFactory.logger(toFileDescriptor: fileDescriptor, closeOnEndOfFile: true))
    }
    return IDBLogger(loggers: loggers).dateFormatted()
  }

  /// The stderr-only logger. Nothing about it can fail, so a caller can build one to report
  /// a failure of `logger(withUserDefaults:)` itself.
  public static func systemLogger(withUserDefaults userDefaults: UserDefaults) -> IDBLogger {
    IDBLogger(loggers: [systemLoggerSink(withUserDefaults: userDefaults)]).dateFormatted()
  }

  private static func systemLoggerSink(withUserDefaults userDefaults: UserDefaults) -> ControlCoreLogger {
    let debugLogging = userDefaults.string(forKey: "-log-level")?.lowercased() != "info"
    return FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: debugLogging)
  }

  private static func openLogFile(atPath path: String) throws -> Int32 {
    let logFileURL = URL(fileURLWithPath: path)
    let directoryURL = logFileURL.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: [:])
    } catch {
      throw IDBLoggerError.logDirectoryCreationFailed(path: directoryURL.path, underlyingError: error)
    }

    // O_CLOEXEC because the companion spawns processes throughout its life and
    // none of them have any business inheriting the log.
    let fileDescriptor = open(logFileURL.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
    let openError = errno
    guard fileDescriptor >= 0 else {
      throw IDBLoggerError.logFileOpenFailed(path: logFileURL.path, code: openError)
    }
    return fileDescriptor
  }

  public override var loggers: [ControlCoreLogger] {
    super.loggers + globalLoggers.all
  }

  /// `FBCompositeLogger`'s builder methods allocate an instance of the receiver's dynamic class, so
  /// applying one to an `IDBLogger` always yields an `IDBLogger` — the `ControlCoreLogger`
  /// requirements can only promise `ControlCoreLogger`.
  public func named(_ name: String) -> IDBLogger {
    unsafeDowncast(withName(name) as AnyObject, to: IDBLogger.self)
  }

  func dateFormatted() -> IDBLogger {
    unsafeDowncast(withDateFormatEnabled(true) as AnyObject, to: IDBLogger.self)
  }

  func tailToConsumer(_ consumer: DataConsumer) async throws -> any LogOperation {
    let logger = FBControlCoreLoggerFactory.logger(to: consumer)
    globalLoggers.add(logger)
    return IDBLoggerOperation(consumer: consumer, logger: logger)
  }
}
