/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

//
// These are written as standalone functions because Swift does not allow
// extension methods on generic Objective-C classes to access the class's
// generic parameters. `FBSubprocess<StdInType, StdOutType, StdErrType>` is
// such a class.

/// Awaits the exit code of `subprocess`.
///
/// Throws if the process was signalled rather than exiting normally,
/// matching the behaviour of `-[FBSubprocess exitCode]`.
public func awaitExitCode<StdIn, StdOut, StdErr>(
  of subprocess: FBSubprocess<StdIn, StdOut, StdErr>
) async throws -> Int32 {
  let value = try await bridgeFBFuture(subprocess.exitCode)
  return value.int32Value
}
