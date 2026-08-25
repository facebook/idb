/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Shared failure for commands whose weakly-held device has been deallocated,
/// replacing the per-command copies of the same case.
public enum FBDeviceNilError: Error, LocalizedError {
  case deviceNil

  public var errorDescription: String? {
    switch self {
    case .deviceNil:
      return "Device is nil"
    }
  }
}
