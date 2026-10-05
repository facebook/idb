/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum ProfileError: Error, Equatable, LocalizedError {
  case toolFailed(tool: String, exitCode: Int32, stderr: String)
  /// The tool succeeded but left nothing to report.
  case noReport(tool: String, output: String)
  /// Only `trace` can launch an application or record every process.
  case unsupportedTarget(ProfileTarget)
  case traceSchemaMissing(schema: String, available: [String])

  public var errorDescription: String? {
    switch self {
    case let .toolFailed(tool, exitCode, stderr):
      return "\(tool) exited with code \(exitCode): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
    case let .noReport(tool, output):
      return "\(tool) wrote no report: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
    case let .unsupportedTarget(target):
      return "Only trace can profile \(target)"
    case let .traceSchemaMissing(schema, available):
      return "The trace has no \(schema) table. It has: \(available.joined(separator: ", "))"
    }
  }
}
