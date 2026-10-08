/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// A test double logger that captures all logged messages for assertion.
// SAFETY: writes are serialized by `lock`; tests read `messages` after the work under test finishes.
final class CapturingLogger: NSObject, ControlCoreLogger, @unchecked Sendable {
  let messages = NSMutableArray()
  private let lock = NSLock()

  @discardableResult
  func log(_ message: String) -> ControlCoreLogger {
    lock.lock()
    defer { lock.unlock() }
    messages.add(message)
    return self
  }

  func info() -> ControlCoreLogger { self }
  func debug() -> ControlCoreLogger { self }
  func error() -> ControlCoreLogger { self }
  func withName(_ prefix: String) -> ControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> ControlCoreLogger { self }
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }
}
