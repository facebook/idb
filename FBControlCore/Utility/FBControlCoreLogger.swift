/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A Protocol for Classes that receive Logger Messages.
@objc public protocol FBControlCoreLogger: NSObjectProtocol {
  /// Logs a Message with the provided String.
  @discardableResult
  func log(_ message: String) -> FBControlCoreLogger

  /// Returns the Info Logger variant.
  func info() -> FBControlCoreLogger

  /// Returns the Debug Logger variant.
  func debug() -> FBControlCoreLogger

  /// Returns the Error Logger variant.
  func error() -> FBControlCoreLogger

  /// Returns a Logger for a named 'facility' or 'tag'.
  func withName(_ name: String) -> FBControlCoreLogger

  /// Enables or Disables date formatting in the logger.
  func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger

  /// The Prefix for the Logger, if set.
  var name: String? { get }

  /// The Current Log Level.
  var level: FBControlCoreLogLevel { get }
}

// MARK: - Conformance extensions for ObjC classes

extension FBCompositeLogger: FBControlCoreLogger {}
