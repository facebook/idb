/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import os

/// The Log Level.
/// The Multiple Level exists so that composite loggers can decide whether to log individually.
public enum ControlCoreLogLevel: Sendable {
  case error
  case info
  case debug
  case multiple
}

/// Receives log messages. Conformers must be thread-safe: loggers are shared across queues,
/// private-framework callback threads and actors.
public protocol ControlCoreLogger: AnyObject, Sendable {
  /// Logs a Message with the provided String.
  @discardableResult
  func log(_ message: String) -> ControlCoreLogger

  /// Returns the Info Logger variant.
  func info() -> ControlCoreLogger

  /// Returns the Debug Logger variant.
  func debug() -> ControlCoreLogger

  /// Returns the Error Logger variant.
  func error() -> ControlCoreLogger

  /// Returns a Logger for a named 'facility' or 'tag'.
  func withName(_ name: String) -> ControlCoreLogger

  /// Enables or Disables date formatting in the logger.
  func withDateFormatEnabled(_ enabled: Bool) -> ControlCoreLogger

  /// The Prefix for the Logger, if set.
  var name: String? { get }

  /// The Current Log Level.
  var level: ControlCoreLogLevel { get }
}

/// Trims surrounding whitespace and newlines; returns nil when nothing remains to log.
func loggableStringLine(_ string: String) -> String? {
  let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

// MARK: - OSLogLogger

// SAFETY: all state is immutable, and `OSLog` handles are safe to use from any thread.
final class OSLogLogger: ControlCoreLogger, @unchecked Sendable {

  static let subsystem = "com.facebook.fbcontrolcore"

  private let client: OSLog
  let name: String?
  let level: ControlCoreLogLevel

  init(client: OSLog, name: String?, level: ControlCoreLogLevel) {
    self.client = client
    self.name = name
    self.level = level
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

// SAFETY: all state is immutable; writes to the shared consumer are serialized by `writeLock`,
// which loggers derived from one another share along with the consumer.
/// Logs each message as a line of text to a data consumer.
public final class ConsumerLogger: ControlCoreLogger, @unchecked Sendable {

  private let consumer: DataConsumer
  private let writeLock: NSLock
  private let dateFormatter: DateFormatter?
  public let name: String?

  // Nothing filters on a consumer logger's level; it writes every message.
  public var level: ControlCoreLogLevel {
    .info
  }

  /// Logs to `consumer`.
  public convenience init(consumer: DataConsumer) {
    self.init(consumer: consumer, name: nil, dateFormatter: nil)
  }

  /// Logs to `fileDescriptor`, closing it on end of file if `closeOnEndOfFile` is set.
  public convenience init(fileDescriptor: Int32, closeOnEndOfFile: Bool) {
    self.init(consumer: FileWriter.syncWriter(withFileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile))
  }

  init(consumer: DataConsumer, name: String?, dateFormatter: DateFormatter?, writeLock: NSLock = NSLock()) {
    self.consumer = consumer
    self.writeLock = writeLock
    self.name = name
    self.dateFormatter = dateFormatter
  }

  @discardableResult
  public func log(_ message: String) -> ControlCoreLogger {
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
    writeLock.withLock {
      consumer.consumeData(Data(line.utf8))
    }
    return self
  }

  public func info() -> ControlCoreLogger {
    self
  }

  public func debug() -> ControlCoreLogger {
    self
  }

  public func error() -> ControlCoreLogger {
    self
  }

  public func withName(_ name: String) -> ControlCoreLogger {
    ConsumerLogger(consumer: consumer, name: name, dateFormatter: dateFormatter, writeLock: writeLock)
  }

  public func withDateFormatEnabled(_ enabled: Bool) -> ControlCoreLogger {
    guard enabled else {
      return ConsumerLogger(consumer: consumer, name: name, dateFormatter: nil, writeLock: writeLock)
    }
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZZZ"
    return ConsumerLogger(consumer: consumer, name: name, dateFormatter: dateFormatter, writeLock: writeLock)
  }
}
