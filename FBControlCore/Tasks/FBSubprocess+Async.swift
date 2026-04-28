/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors emitted while bridging an `FBFuture` to Swift `async`/`await`.
public enum FBSubprocessAsyncError: Error {
  /// The underlying future signalled completion without yielding a value or
  /// an error. This indicates a bug in the producing FBFuture implementation.
  case continuationFulfilledWithoutValues
}

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

// MARK: - FBFuture bridge
//
// Mirrors the `BridgeFuture.value` pattern used in CompanionLib but is inlined
// here because FBControlCore sits below CompanionLib in the dependency stack.
// It will be removed once `FBSubprocess` itself is converted to a Swift-native
// async API.

/// Wraps a non-Sendable `FBFuture` so it can be captured by `@Sendable`
/// closures (the cancellation handler). FBFuture is internally serialised
/// by its own dispatch queue, so this is safe in practice.
private final class FBFutureBox<T: AnyObject>: @unchecked Sendable {
  let future: FBFuture<T>
  init(_ future: FBFuture<T>) {
    self.future = future
  }
}

private func bridgeFBFuture<T: AnyObject & Sendable>(_ future: FBFuture<T>) async throws -> T {
  let box = FBFutureBox(future)
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { continuation in
      box.future.onQueue(
        asyncBridgeQueue,
        notifyOfCompletion: { resolved in
          if let error = resolved.error {
            continuation.resume(throwing: error)
          } else if let value = resolved.result {
            // swiftlint:disable:next force_cast
            continuation.resume(returning: value as! T)
          } else {
            continuation.resume(throwing: FBSubprocessAsyncError.continuationFulfilledWithoutValues)
          }
        })
    }
  } onCancel: {
    box.future.cancel()
  }
}

private let asyncBridgeQueue = DispatchQueue(label: "com.facebook.fbcontrolcore.subprocess.async_bridge")
