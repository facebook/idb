/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Describes which exit codes from an in-simulator tool count as success.
///
/// Some tools (`launchctl`) return errno-style codes, so a benign condition such as "service not
/// running" (`ESRCH`, 3) can be told apart from a genuine failure and accepted explicitly. Others
/// (`defaults`) collapse a missing key and a real error onto the same non-zero code, so they can only
/// tolerate everything.
enum ExitCodePolicy {
  /// The listed exit codes count as success; any other is a failure.
  case require(Set<Int32>)
  /// Any exit code is accepted; the caller logs a non-zero one.
  case tolerateAny

  func accepts(_ exitCode: Int32) -> Bool {
    switch self {
    case let .require(codes):
      return codes.contains(exitCode)
    case .tolerateAny:
      return true
    }
  }
}
