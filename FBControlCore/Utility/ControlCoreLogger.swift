/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

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
