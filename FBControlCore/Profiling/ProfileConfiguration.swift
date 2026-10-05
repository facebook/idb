/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// What to profile, with the options that apply to it.
public enum ProfileConfiguration: Equatable, Sendable {
  /// Leaked allocations, with the stack that allocated each.
  case leaks
  /// A memory graph written to `outputPath`, reported as `leaks` reports it.
  case memgraph(outputPath: String)
  /// Live heap allocations, grouped by class.
  case heap
  /// Call stacks sampled for `seconds`.
  case sample(seconds: UInt)
  /// Virtual memory, summarised by region type.
  case vmmap
  /// Physical memory footprint, by category.
  case footprint
  /// Resource usage sampled every `interval` until the target exits or the operation is stopped.
  case resources(interval: Duration, scope: ResourceSampleScope)
}
