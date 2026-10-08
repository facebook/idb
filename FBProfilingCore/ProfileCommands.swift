/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

public protocol ProfileCommands {

  /// Starts profiling `target`. Throws if the target can't be resolved; the profiler's own failures surface from
  /// `ProfileOperation.result`.
  func profile(_ configuration: ProfileConfiguration, target: ProfileTarget) async throws -> ProfileOperation
}
