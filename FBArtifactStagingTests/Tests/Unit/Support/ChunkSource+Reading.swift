/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
import Foundation

extension ChunkSource {

  /// Calls `body` with this source, for tests that read one in a scope as a stream arriving would be.
  func reading<T>(_ body: (any ByteSource) async throws -> T) async rethrows -> T {
    try await body(self)
  }
}
