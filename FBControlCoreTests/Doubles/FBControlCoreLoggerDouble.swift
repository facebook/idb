// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore

/// A Double of a Logger that does nothing.
final class FBControlCoreLoggerDouble: NSObject, FBControlCoreLogger {
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }

  func log(_ message: String) -> any FBControlCoreLogger { self }
  func info() -> any FBControlCoreLogger { self }
  func debug() -> any FBControlCoreLogger { self }
  func error() -> any FBControlCoreLogger { self }
  func withName(_ name: String) -> any FBControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any FBControlCoreLogger { self }
}
