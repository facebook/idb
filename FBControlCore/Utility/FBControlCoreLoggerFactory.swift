/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import os

/// Implementations of Loggers.
public enum FBControlCoreLoggerFactory {

  /// A logger backed by os_log.
  /// `writeToStdErr` additionally mirrors output to stderr unless os_log already does so in this environment.
  /// `debugLogging` selects the debug level rather than info.
  public static func systemLoggerWriting(toStderr writeToStdErr: Bool, withDebugLogging debugLogging: Bool) -> ControlCoreLogger {
    let systemLogger = OSLogLogger(client: OSLog(subsystem: OSLogLogger.subsystem, category: ""), name: nil, level: debugLogging ? .debug : .info)
    guard writeToStdErr, !systemLoggerWillLogToStdErr else {
      return systemLogger
    }
    return compositeLogger(with: [
      systemLogger,
      logger(toFileDescriptor: STDERR_FILENO, closeOnEndOfFile: false),
    ])
  }

  /// Compose multiple loggers into one.
  public static func compositeLogger(with loggers: [ControlCoreLogger]) -> FBCompositeLogger {
    FBCompositeLogger(loggers: loggers)
  }

  /// Log to a Consumer.
  public static func logger(to consumer: DataConsumer) -> ControlCoreLogger {
    ConsumerLogger(consumer: consumer, name: nil, dateFormatter: nil)
  }

  /// Log to a File Descriptor, closing it on end of file if `closeOnEndOfFile` is set.
  public static func logger(toFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool) -> ControlCoreLogger {
    logger(to: FileWriter.syncWriter(withFileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile))
  }

  // rdar://36919139: os_log writes to stderr itself when any of these are set.
  private static var systemLoggerWillLogToStdErr: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["OS_ACTIVITY_DT_MODE"] != nil || environment["ACTIVITY_LOG_STDERR"] != nil || environment["CFLOG_FORCE_STDERR"] != nil
  }
}

/// Trims surrounding whitespace and newlines; returns nil when nothing remains to log.
func loggableStringLine(_ string: String) -> String? {
  let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

// MARK: - OSLogLogger

// SAFETY: all state is immutable, and `OSLog` handles are safe to use from any thread.
private final class OSLogLogger: NSObject, ControlCoreLogger, @unchecked Sendable {

  static let subsystem = "com.facebook.fbcontrolcore"

  private let client: OSLog
  let name: String?
  let level: FBControlCoreLogLevel

  init(client: OSLog, name: String?, level: FBControlCoreLogLevel) {
    self.client = client
    self.name = name
    self.level = level
    super.init()
  }

  @discardableResult
  func log(_ message: String) -> ControlCoreLogger {
    os_log("%{public}s", log: client, type: logType, message)
    return self
  }

  func info() -> ControlCoreLogger {
    OSLogLogger(client: client, name: name, level: .info)
  }

  func debug() -> ControlCoreLogger {
    OSLogLogger(client: client, name: name, level: .debug)
  }

  func error() -> ControlCoreLogger {
    OSLogLogger(client: client, name: name, level: .error)
  }

  func withName(_ name: String) -> ControlCoreLogger {
    OSLogLogger(client: OSLog(subsystem: OSLogLogger.subsystem, category: name), name: name, level: level)
  }

  func withDateFormatEnabled(_ enabled: Bool) -> ControlCoreLogger {
    self
  }

  private var logType: OSLogType {
    switch level {
    case .error:
      return .error
    case .info:
      return .info
    case .debug:
      return .debug
    case .multiple:
      return .default
    }
  }
}

// MARK: - ConsumerLogger

// SAFETY: all state is immutable; writes to the shared consumer are serialized on the consumer
// itself, since loggers derived from one another share it.
private final class ConsumerLogger: NSObject, ControlCoreLogger, @unchecked Sendable {

  private let consumer: DataConsumer
  private let dateFormatter: DateFormatter?
  let name: String?

  // Nothing filters on a consumer logger's level; it writes every message.
  var level: FBControlCoreLogLevel {
    .info
  }

  init(consumer: DataConsumer, name: String?, dateFormatter: DateFormatter?) {
    self.consumer = consumer
    self.name = name
    self.dateFormatter = dateFormatter
    super.init()
  }

  @discardableResult
  func log(_ message: String) -> ControlCoreLogger {
    guard let message = loggableStringLine(message) else {
      return self
    }
    var line = ""
    if let dateFormatter {
      line += "\(dateFormatter.string(from: Date())) "
    }
    if let name {
      line += "[\(name)] "
    }
    line += message + "\n"
    objc_sync_enter(consumer)
    defer { objc_sync_exit(consumer) }
    consumer.consumeData(Data(line.utf8))
    return self
  }

  func info() -> ControlCoreLogger {
    self
  }

  func debug() -> ControlCoreLogger {
    self
  }

  func error() -> ControlCoreLogger {
    self
  }

  func withName(_ name: String) -> ControlCoreLogger {
    ConsumerLogger(consumer: consumer, name: name, dateFormatter: dateFormatter)
  }

  func withDateFormatEnabled(_ enabled: Bool) -> ControlCoreLogger {
    guard enabled else {
      return ConsumerLogger(consumer: consumer, name: name, dateFormatter: nil)
    }
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZZZ"
    return ConsumerLogger(consumer: consumer, name: name, dateFormatter: dateFormatter)
  }
}
