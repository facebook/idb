/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Thrown when a command's weakly-held target (a simulator, device, or `self`) was deallocated
/// before the command ran.
public enum FBWeakTargetError: Error, CustomStringConvertible, LocalizedError {
  /// `target` is a human-readable description of what was deallocated, e.g. "Simulator".
  case deallocated(String)

  /// A deallocated `FBSimulator`.
  public static let simulator = FBWeakTargetError.deallocated("Simulator")

  public var description: String {
    switch self {
    case let .deallocated(target):
      return "\(target) deallocated"
    }
  }

  public var errorDescription: String? { description }
}
