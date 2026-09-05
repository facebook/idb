/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore

// SAFETY: stateless no-op.
final class FBControlCoreLoggerDouble: NSObject, FBControlCoreLogger, @unchecked Sendable {
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }

  func log(_ message: String) -> any FBControlCoreLogger { self }
  func info() -> any FBControlCoreLogger { self }
  func debug() -> any FBControlCoreLogger { self }
  func error() -> any FBControlCoreLogger { self }
  func withName(_ name: String) -> any FBControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any FBControlCoreLogger { self }
}
