/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum ProfileError: Error, Equatable, LocalizedError {
  case toolFailed(tool: String, exitCode: Int32, stderr: String)

  public var errorDescription: String? {
    switch self {
    case let .toolFailed(tool, exitCode, stderr):
      return "\(tool) exited with code \(exitCode): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
  }
}
