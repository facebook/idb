/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - Public API
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

/// Awaits `subprocess` to exit with one of the given codes.
///
/// Throws if the process exits with a status not in `codes`, or if it is
/// signalled. Mirrors `-[FBSubprocess exitedWithCodes:]`.
public func awaitExit<StdIn, StdOut, StdErr>(
  of subprocess: FBSubprocess<StdIn, StdOut, StdErr>,
  withCodes codes: Set<Int32>
) async throws {
  let acceptable: Set<NSNumber> = Set(codes.map { NSNumber(value: $0) })
  _ = try await bridgeFBFuture(subprocess.exited(withCodes: acceptable))
}

/// Builds and starts the process described by `builder` and returns the
/// spawned `FBSubprocess`.
///
/// Async wrapper around `-[FBProcessBuilder start]`.
public func awaitStart<StdIn, StdOut, StdErr>(
  of builder: FBProcessBuilder<StdIn, StdOut, StdErr>
) async throws -> FBSubprocess<StdIn, StdOut, StdErr> {
  try await bridgeFBFuture(builder.start())
}

/// Builds, starts and waits for the process described by `builder` to finish.
/// Returns the resulting `FBSubprocess`.
///
/// Async wrapper around `-[FBProcessBuilder runUntilCompletionWithAcceptableExitCodes:]`.
/// Pass `nil` to accept any exit code.
public func awaitRunUntilCompletion<StdIn, StdOut, StdErr>(
  of builder: FBProcessBuilder<StdIn, StdOut, StdErr>,
  withAcceptableExitCodes acceptableExitCodes: Set<Int32>?
) async throws -> FBSubprocess<StdIn, StdOut, StdErr> {
  let codes: Set<NSNumber>? = acceptableExitCodes.map { Set($0.map { NSNumber(value: $0) }) }
  return try await bridgeFBFuture(builder.runUntilCompletion(withAcceptableExitCodes: codes))
}
