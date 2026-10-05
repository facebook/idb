/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public struct ProfileResult: Equatable, Sendable {
  /// Nil for `resources`, which reports through `ProfileOperation.samples` instead.
  public let report: ProfileReport?
  /// What the tool wrote, unparsed: text for most tools, JSON for `footprint`.
  public let toolOutput: Data
  /// The file the profiler wrote, such as a memory graph or a trace.
  public let artifact: URL?

  public init(report: ProfileReport?, toolOutput: Data, artifact: URL?) {
    self.report = report
    self.toolOutput = toolOutput
    self.artifact = artifact
  }
}
