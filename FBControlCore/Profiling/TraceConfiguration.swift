/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public struct TraceConfiguration: Equatable, Sendable {
  /// The Instruments template to record with, by name or path.
  public let template: String
  /// The tables to export, by schema. Nil exports the tables the template is known for, such as `time-profile` for
  /// Time Profiler, and nothing for other templates.
  public let schemas: [String]?
  public let timeLimit: Duration
  /// The most rows of each table to report. Every row is still counted.
  public let rowLimit: Int?
  /// Where to keep the `.trace`. Nil records to a temporary file that is removed once exported.
  public let outputPath: String?

  public init(template: String, schemas: [String]?, timeLimit: Duration, rowLimit: Int?, outputPath: String?) {
    self.template = template
    self.schemas = schemas
    self.timeLimit = timeLimit
    self.rowLimit = rowLimit
    self.outputPath = outputPath
  }
}
