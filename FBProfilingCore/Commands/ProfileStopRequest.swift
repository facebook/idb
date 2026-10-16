/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Asks a running profiler to finish early and report what it has recorded so far.
public final class ProfileStopRequest: Sendable {
  private let requested = AsyncEvent<Void>()

  init() {}

  func request() {
    requested.happen()
  }

  /// Returns once a stop has been requested. Throws only `CancellationError`.
  public func wait() async throws {
    try await requested.wait()
  }
}
