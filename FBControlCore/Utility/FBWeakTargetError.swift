/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Raised when a command's weakly-held target has been deallocated before the command could run.
///
/// Command classes hold their target (a simulator, device, or `self`) `weak` to avoid retain cycles,
/// so every operation must first re-check it. This is the shared error for that guard, replacing
/// per-surface `deallocated` cases and the stringly-typed `FB*Error.describe("… deallocated")`.
public enum FBWeakTargetError: Error, CustomStringConvertible, LocalizedError {
  /// `target` is a human-readable description of what was deallocated, e.g. "Simulator".
  case deallocated(String)

  /// The common case: a weakly-held `FBSimulator` was deallocated. Prefer this over
  /// hand-writing `.deallocated("Simulator")` at the call site.
  public static let simulator = FBWeakTargetError.deallocated("Simulator")

  public var description: String {
    switch self {
    case let .deallocated(target):
      return "\(target) deallocated"
    }
  }

  public var errorDescription: String? { description }
}
