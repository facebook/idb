/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A composite logger that logs to many loggers.
// SAFETY: holds only an immutable array of child loggers, which are themselves required to be
// thread-safe by the `ControlCoreLogger` contract.
public final class CompositeLogger: ControlCoreLogger, @unchecked Sendable {

  /// The loggers to log to.
  public let loggers: [ControlCoreLogger]

  public init(loggers: [ControlCoreLogger]) {
    self.loggers = loggers
  }

  @discardableResult
  public func log(_ message: String) -> ControlCoreLogger {
    guard let message = loggableStringLine(message) else {
      return self
    }
    for logger in loggers {
      logger.log(message)
    }
    return self
  }

  public func info() -> ControlCoreLogger {
    applying { $0.info() }
  }

  public func debug() -> ControlCoreLogger {
    applying { $0.debug() }
  }

  public func error() -> ControlCoreLogger {
    applying { $0.error() }
  }

  public func withName(_ name: String) -> ControlCoreLogger {
    applying { $0.withName(name) }
  }

  public func withDateFormatEnabled(_ enabled: Bool) -> ControlCoreLogger {
    applying { $0.withDateFormatEnabled(enabled) }
  }

  public var name: String? {
    nil
  }

  public var level: ControlCoreLogLevel {
    .multiple
  }

  private func applying(_ transform: (ControlCoreLogger) -> ControlCoreLogger) -> ControlCoreLogger {
    CompositeLogger(loggers: loggers.map(transform))
  }
}
